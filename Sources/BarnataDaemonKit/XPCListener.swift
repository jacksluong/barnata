import BarnataCore
import Foundation

/// Owns the Mach service listener, the supervisor, and the idle exit timer
public final class XPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    public static let idleTimeout: TimeInterval = 60
    private static let idleCheckInterval: TimeInterval = 5

    private let listener: NSXPCListener
    private let clientRequirement: String?
    private let service: DaemonService
    private let queue = DispatchQueue(label: "io.jackyluong.barnata.listener")
    private var idleSince: Date?
    private var idleTimer: DispatchSourceTimer?

    public override convenience init() {
        self.init(layout: BundleLayout(), machServiceName: barnataMachServiceName)
    }

    public init(layout: BundleLayout, machServiceName: String) {
        self.listener = NSXPCListener(machServiceName: machServiceName)

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
                requirement: teamID.map { barnataCodeSigningRequirement(teamID: $0, identifier: barnataKanataIdentifier) }
            ),
            spawner: spawner,
            logWriter: logWriter,
            onChange: { _ in holder.service?.supervisorDidChange() }
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
        startIdleTimer()
        listener.resume()
        dispatchMain()
    }

    public func noteActivity() {
        queue.async { self.idleSince = nil }
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
        connection.invalidationHandler = { [weak self] in self?.noteActivity() }
        connection.resume()
        noteActivity()
        log.info("accepted a connection from uid \(connection.effectiveUserIdentifier)")
        return true
    }

    // MARK: - Idle exit

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + XPCListener.idleCheckInterval, repeating: XPCListener.idleCheckInterval)
        timer.setEventHandler { [weak self] in self?.checkIdle() }
        timer.resume()
        idleTimer = timer
    }

    private func checkIdle() {
        guard !service.isBusy else {
            idleSince = nil
            return
        }
        guard let since = idleSince else {
            idleSince = Date()
            return
        }
        guard Date().timeIntervalSince(since) >= XPCListener.idleTimeout else { return }
        log.notice("idle for \(XPCListener.idleTimeout, privacy: .public) s, exiting")
        service.terminateChildren()
        exit(0)
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
