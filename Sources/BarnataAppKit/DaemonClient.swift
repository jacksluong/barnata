import BarnataCore
import Foundation

/// XPC client for the root daemon. Reconnects with backoff and keeps a push subscription alive.
public final class DaemonClient: NSObject, @unchecked Sendable {
    public enum Event: Sendable {
        case connected(daemonVersion: String)
        case status(DaemonStatus)
        case disconnected
    }

    public static let backoffDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    private let machServiceName: String
    private let queue = DispatchQueue(label: "io.jackyluong.barnata.daemon-client")
    private var connection: NSXPCConnection?
    private var subscription: NSXPCListener?
    private var subscriptionDelegate: SubscriptionDelegate?
    private var attempt = 0
    private var isStopped = true

    /// Delivered on the main queue
    public var onEvent: (@Sendable (Event) -> Void)?

    public init(machServiceName: String = barnataMachServiceName) {
        self.machServiceName = machServiceName
        super.init()
    }

    public func start() {
        queue.async {
            guard self.isStopped else { return }
            self.isStopped = false
            self.attempt = 0
            self.openConnection()
        }
    }

    public func stop() {
        queue.async {
            self.isStopped = true
            self.teardown()
        }
    }

    /// Drops the connection and lets the backoff bring up whatever launchd starts next
    public func reconnect() {
        queue.async {
            guard !self.isStopped else { return }
            self.teardown()
            self.attempt = 0
            self.scheduleReconnect()
        }
    }

    // MARK: - Requests

    public func version(_ completion: @escaping @Sendable (String?) -> Void) {
        withProxy({ completion(nil) }) { proxy in
            proxy.version { value in DispatchQueue.main.async { completion(value) } }
        }
    }

    public func status(_ completion: @escaping @Sendable (DaemonStatus?) -> Void) {
        withProxy({ completion(nil) }) { proxy in
            proxy.status { data in
                let status = try? Envelope.decode(DaemonStatus.self, from: data)
                DispatchQueue.main.async { completion(status) }
            }
        }
    }

    public func start(_ request: StartRequest, completion: @escaping @Sendable (CommandResult) -> Void) {
        guard let payload = try? Envelope.encode(request) else {
            return DispatchQueue.main.async { completion(.failure("cannot encode the start request")) }
        }
        command(completion) { proxy, reply in proxy.start(request: payload, reply: reply) }
    }

    public func stopKanata(_ completion: @escaping @Sendable (CommandResult) -> Void) {
        command(completion) { proxy, reply in proxy.stop(reply: reply) }
    }

    public func restartKanata(_ completion: @escaping @Sendable (CommandResult) -> Void) {
        command(completion) { proxy, reply in proxy.restart(reply: reply) }
    }

    public func shutdownDaemon(_ completion: @escaping @Sendable (CommandResult) -> Void) {
        command(completion) { proxy, reply in proxy.shutdown(reply: reply) }
    }

    public func installDriver(_ completion: @escaping @Sendable (CommandResult) -> Void) {
        command(completion) { proxy, reply in proxy.installDriver(reply: reply) }
    }

    public func activateDriver(_ completion: @escaping @Sendable (CommandResult) -> Void) {
        command(completion) { proxy, reply in proxy.activateDriver(reply: reply) }
    }

    // MARK: - Queue-confined internals

    private func openConnection() {
        guard !isStopped, connection == nil else { return }

        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: BarnataDaemonProtocol.self)
        connection.invalidationHandler = { [weak self] in self?.handleDrop(reason: "invalidated") }
        connection.interruptionHandler = { [weak self] in self?.handleDrop(reason: "interrupted") }
        connection.resume()
        self.connection = connection

        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            log.error("daemon handshake failed: \(error.localizedDescription, privacy: .public)")
            self?.handleDrop(reason: "handshake failed")
        } as? BarnataDaemonProtocol

        // NSXPCConnection is not Sendable, so the handshake reply carries a token instead of the object
        let token = ObjectIdentifier(connection)
        proxy?.version { [weak self] version in
            guard let self else { return }
            queue.async {
                guard let live = self.connection, ObjectIdentifier(live) == token else { return }
                self.attempt = 0
                self.installSubscription(on: live)
                self.emit(.connected(daemonVersion: version))
            }
        }
    }

    private func installSubscription(on connection: NSXPCConnection) {
        let listener = NSXPCListener.anonymous()
        let delegate = SubscriptionDelegate(
            requirement: CodeSignature.selfTeamIdentifier().map {
                barnataCodeSigningRequirement(teamID: $0, identifier: barnataDaemonIdentifier)
            },
            onStatus: { [weak self] status in self?.emit(.status(status)) }
        )
        listener.delegate = delegate
        listener.resume()

        subscription = listener
        subscriptionDelegate = delegate
        (connection.remoteObjectProxy as? BarnataDaemonProtocol)?.subscribe(client: listener.endpoint)
    }

    private func handleDrop(reason: String) {
        queue.async {
            guard !self.isStopped, self.connection != nil else { return }
            log.notice("daemon connection \(reason, privacy: .public)")
            self.teardown()
            self.emit(.disconnected)
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !isStopped else { return }
        let delay = DaemonClient.backoffDelays[min(attempt, DaemonClient.backoffDelays.count - 1)]
        attempt += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.openConnection() }
    }

    private func teardown() {
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        subscription?.invalidate()
        subscription = nil
        subscriptionDelegate = nil
    }

    /// Hands the caller a proxy, or runs `unavailable` when there is no live connection
    private func withProxy(
        _ unavailable: @escaping @Sendable () -> Void,
        _ body: @escaping @Sendable (BarnataDaemonProtocol) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, let connection = self.connection else {
                return DispatchQueue.main.async(execute: unavailable)
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                log.error("daemon request failed: \(error.localizedDescription, privacy: .public)")
                self?.handleDrop(reason: "request failed")
                DispatchQueue.main.async(execute: unavailable)
            } as? BarnataDaemonProtocol
            guard let proxy else { return DispatchQueue.main.async(execute: unavailable) }
            body(proxy)
        }
    }

    private func command(
        _ completion: @escaping @Sendable (CommandResult) -> Void,
        _ body: @escaping @Sendable (BarnataDaemonProtocol, @escaping (Data) -> Void) -> Void
    ) {
        withProxy({ completion(.failure("the daemon is not reachable")) }) { proxy in
            body(proxy) { data in
                let result = (try? Envelope.decode(CommandResult.self, from: data))
                    ?? .failure("the daemon sent an unreadable reply")
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    private func emit(_ event: Event) {
        guard let onEvent else { return }
        DispatchQueue.main.async { onEvent(event) }
    }
}

/// Receives the daemon's pushed status changes over an anonymous listener
private final class SubscriptionDelegate: NSObject, NSXPCListenerDelegate, BarnataClientProtocol, @unchecked Sendable {
    private let requirement: String?
    private let onStatus: @Sendable (DaemonStatus) -> Void

    init(requirement: String?, onStatus: @escaping @Sendable (DaemonStatus) -> Void) {
        self.requirement = requirement
        self.onStatus = onStatus
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement { connection.setCodeSigningRequirement(requirement) }
        connection.exportedInterface = NSXPCInterface(with: BarnataClientProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func statusDidChange(status: Data) {
        guard let decoded = try? Envelope.decode(DaemonStatus.self, from: status) else { return }
        onStatus(decoded)
    }
}
