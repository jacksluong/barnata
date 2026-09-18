import BarnataCore
import Foundation

/// The object the app talks to over XPC. State is guarded by `queue`.
final class DaemonService: NSObject, BarnataDaemonProtocol, @unchecked Sendable {
    private let layout: BundleLayout
    private let validator: RequestValidator
    private let supervisor: ProcessSupervisor
    private let driverManager: DriverManager
    private let queue = DispatchQueue(label: "io.jackyluong.barnata.service")
    private var subscribers: [NSXPCConnection] = []
    private var cachedKanataVersion: String?
    private let onIdleChange: @Sendable () -> Void

    init(
        layout: BundleLayout,
        validator: RequestValidator,
        supervisor: ProcessSupervisor,
        driverManager: DriverManager,
        onIdleChange: @escaping @Sendable () -> Void
    ) {
        self.layout = layout
        self.validator = validator
        self.supervisor = supervisor
        self.driverManager = driverManager
        self.onIdleChange = onIdleChange
    }

    // MARK: - BarnataDaemonProtocol

    func version(reply: @escaping (String) -> Void) {
        reply(DaemonService.bundleVersion(layout: layout))
    }

    func status(reply: @escaping (Data) -> Void) {
        reply(encode(currentStatus()))
    }

    func start(request data: Data, reply: @escaping (Data) -> Void) {
        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else {
            return reply(encode(CommandResult.failure("cannot identify the calling user")))
        }
        guard let request = try? Envelope.decode(StartRequest.self, from: data) else {
            return reply(encode(CommandResult.failure("malformed start request")))
        }

        let validated: ValidatedStartRequest
        do {
            validated = try validator.validate(request, ownerUID: uid)
        } catch {
            log.error("rejected a start request: \(error, privacy: .public)")
            return reply(encode(CommandResult.failure("\(error)")))
        }

        let driver = driverManager.ensureVirtualHIDDaemon()
        guard driver.ok else { return reply(encode(driver)) }

        log.notice("starting preset \(validated.presetName, privacy: .public) for uid \(uid)")
        reply(encode(supervisor.start(validated)))
    }

    func stop(reply: @escaping (Data) -> Void) {
        let result = supervisor.stop()
        driverManager.stopVirtualHIDDaemon()
        reply(encode(result))
    }

    func restart(reply: @escaping (Data) -> Void) {
        reply(encode(supervisor.restart()))
    }

    /// Replies once the children are really gone, so a quitting app can wait for it
    func shutdown(reply: @escaping (Data) -> Void) {
        log.notice("shutting down on request")
        terminateChildren()
        reply(encode(CommandResult.success))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
    }

    func ensureVirtualHIDDaemon(reply: @escaping (Data) -> Void) {
        reply(encode(driverManager.ensureVirtualHIDDaemon()))
    }

    func installDriver(reply: @escaping (Data) -> Void) {
        reply(encode(driverManager.installDriver()))
    }

    func activateDriver(reply: @escaping (Data) -> Void) {
        reply(encode(driverManager.activateDriver()))
    }

    func subscribe(client endpoint: NSXPCListenerEndpoint) {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: BarnataClientProtocol.self)
        connection.invalidationHandler = { [weak self] in self?.removeSubscriber(connection) }
        connection.interruptionHandler = { [weak self] in self?.removeSubscriber(connection) }
        connection.resume()
        queue.sync { subscribers.append(connection) }
        push(currentStatus())
    }

    // MARK: - Daemon lifecycle

    /// True while the app holds a status subscription
    var hasClients: Bool {
        !queue.sync { subscribers.isEmpty }
    }

    /// True while kanata or the virtual HID daemon is running under this daemon
    var hasRunningChildren: Bool {
        supervisor.isBusy || driverManager.isRunningVirtualHIDDaemon
    }

    func terminateChildren() {
        supervisor.terminateNow()
        driverManager.terminateVirtualHIDDaemon()
    }

    func supervisorDidChange(_ snapshot: SupervisorSnapshot) {
        push(currentStatus(snapshot))
        onIdleChange()
    }

    // MARK: - Internals

    private func currentStatus(_ provided: SupervisorSnapshot? = nil) -> DaemonStatus {
        let snapshot = provided ?? supervisor.snapshot
        return DaemonStatus(
            daemonVersion: DaemonService.bundleVersion(layout: layout),
            kanataVersion: kanataVersion(),
            state: snapshot.state,
            pid: snapshot.pid,
            presetName: snapshot.presetName,
            configPaths: snapshot.configPaths,
            tcpPort: snapshot.tcpPort,
            ownerUID: snapshot.ownerUID,
            lastExitCode: snapshot.lastExitCode,
            lastError: snapshot.lastError,
            restartCount: snapshot.restartCount,
            driver: driverManager.status
        )
    }

    private func push(_ status: DaemonStatus) {
        let payload = encode(status)
        for connection in queue.sync(execute: { subscribers }) {
            (connection.remoteObjectProxy as? BarnataClientProtocol)?.statusDidChange(status: payload)
        }
    }

    private func removeSubscriber(_ connection: NSXPCConnection) {
        queue.sync { subscribers.removeAll { $0 === connection } }
        onIdleChange()
    }

    private func kanataVersion() -> String? {
        queue.sync {
            if let cachedKanataVersion { return cachedKanataVersion }
            let result = Command.run(layout.kanataURL.path, ["--version"])
            guard result.exitCode == 0 else { return nil }
            let version = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            cachedKanataVersion = version
            return version
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? Envelope.encode(value)) ?? Data()
    }

    /// CFBundleVersion from the embedded Info.plist, falling back to the enclosing app bundle
    static func bundleVersion(layout: BundleLayout) -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String { return version }
        let contentsPlist = layout.macOSDirectory.deletingLastPathComponent().appending(path: "Info.plist")
        guard let data = try? Data(contentsOf: contentsPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleVersion"] as? String
        else { return "0" }
        return version
    }
}
