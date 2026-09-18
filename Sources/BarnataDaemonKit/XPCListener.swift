import BarnataCore
import Foundation

/// Owns the Mach service listener, the supervisor, and the exit timers
public final class XPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    public static let idleTimeout: TimeInterval = 60
    /// How long a client has to come back before its children are torn down with it
    public static let orphanGrace: TimeInterval = 3
    private static let idleCheckInterval: TimeInterval = 5

    private let listener: NSXPCListener
    private let kanataPath: String
    private let clientRequirement: String?
    private let service: DaemonService
    private let queue = DispatchQueue(label: "io.jackyluong.barnata.listener")
    private var idleSince: Date?
    private var idleTimer: DispatchSourceTimer?
    private var orphanTimer: DispatchSourceTimer?
    private var liveConnections = 0

    public override convenience init() {
        self.init(layout: BundleLayout(), machServiceName: barnataMachServiceName)
    }

    public init(layout: BundleLayout, machServiceName: String) {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        self.kanataPath = layout.kanataURL.path

        let teamID = SignatureCheck.selfTeamIdentifier()
        self.clientRequirement = teamID.map {
            barnataCodeSigningRequirement(teamID: $0, identifier: barnataAppBundleIdentifier)
        }

        let requirements = DriverRequirements.load(from: layout.driverRequirementsURL)
            ?? DriverRequirements(requiredVersion: "0", packageName: "")
        let spawner = PosixSpawner()
        let logWriter = LogWriter(url: layout.kanataLogURL)

        let holder = ServiceHolder()
        let supervisor = ProcessSupervisor(
            configuration: ProcessSupervisor.Configuration(
                executablePath: layout.kanataURL.path,
                requirement: teamID.map { barnataCodeSigningRequirement(teamID: $0, identifier: barnataKanataIdentifier) },
                allocatePort: { PortAllocator.allocate() }
            ),
            spawner: spawner,
            logWriter: logWriter,
            onChange: { snapshot in holder.service?.supervisorDidChange(snapshot) }
        )
        let driverManager = DriverManager(
            layout: layout,
            requirements: requirements,
            spawner: spawner,
            logWriter: logWriter
        )

        let holderBox = holder
        self.service = DaemonService(
            layout: layout,
            validator: RequestValidator(),
            supervisor: supervisor,
            driverManager: driverManager,
            onIdleChange: { holderBox.listener?.noteActivity() }
        )

        super.init()
        holder.service = service
        holder.listener = self
        listener.delegate = self
    }

    /// Blocks forever; launchd owns the process lifetime
    public func run() -> Never {
        if clientRequirement == nil {
            log.error("this daemon has no team identifier, every XPC connection will be refused")
        }
        installSignalHandlers()
        reapStrayKanata()
        startIdleTimer()
        listener.resume()
        dispatchMain()
    }

    public func noteActivity() {
        queue.async { self.updateClientState() }
    }

    /// A daemon that died before its child did leaves a kanata holding the keyboard and the TCP port
    private func reapStrayKanata() {
        for pid in StrayProcesses.pids(forExecutable: kanataPath) {
            log.error("killing a stray kanata left by an earlier daemon, pid \(pid)")
            kill(pid, SIGKILL)
        }
    }

    // MARK: - NSXPCListenerDelegate

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let clientRequirement else {
            log.error("refusing a connection because the daemon's own team identifier is unknown")
            return false
        }
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: BarnataDaemonProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self] in self?.noteConnectionClosed() }
        connection.resume()
        noteConnectionOpened()
        log.info("accepted a connection from uid \(connection.effectiveUserIdentifier)")
        return true
    }

    // MARK: - Exit timers

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + XPCListener.idleCheckInterval, repeating: XPCListener.idleCheckInterval)
        timer.setEventHandler { [weak self] in self?.checkIdle() }
        timer.resume()
        idleTimer = timer
    }

    private func checkIdle() {
        guard !hasClients, !service.hasRunningChildren else { return }
        guard let since = idleSince else {
            idleSince = Date()
            return
        }
        guard Date().timeIntervalSince(since) >= XPCListener.idleTimeout else { return }
        log.notice("idle for \(XPCListener.idleTimeout, privacy: .public) s, exiting")
        service.terminateChildren()
        exit(0)
    }

    private func noteConnectionOpened() {
        queue.async {
            self.liveConnections += 1
            self.updateClientState()
        }
    }

    private func noteConnectionClosed() {
        queue.async {
            self.liveConnections = max(0, self.liveConnections - 1)
            self.updateClientState()
        }
    }

    /// Queue-confined: true while any app still holds a connection or a status subscription
    private var hasClients: Bool { liveConnections > 0 || service.hasClients }

    private func updateClientState() {
        guard !hasClients else {
            idleSince = nil
            cancelOrphanTimer()
            return
        }
        if idleSince == nil { idleSince = Date() }
        startOrphanTimer()
    }

    /// A force quit or a crash takes the app's connections with it, and kanata outliving it
    /// would leave the keyboard remapped with nothing left to unmap it
    private func startOrphanTimer() {
        guard orphanTimer == nil, service.hasRunningChildren else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + XPCListener.orphanGrace)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            cancelOrphanTimer()
            guard !hasClients, service.hasRunningChildren else { return }
            log.notice("the app is gone, stopping its children and exiting")
            service.terminateChildren()
            exit(0)
        }
        timer.resume()
        orphanTimer = timer
    }

    private func cancelOrphanTimer() {
        orphanTimer?.cancel()
        orphanTimer = nil
    }

    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in
                log.notice("received signal \(number), terminating children")
                self?.service.terminateChildren()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private var signalSources: [DispatchSourceSignal] = []
}

/// Breaks the cycle between the supervisor's change callback and the service that owns it
private final class ServiceHolder: @unchecked Sendable {
    weak var service: DaemonService?
    weak var listener: XPCListener?
}
