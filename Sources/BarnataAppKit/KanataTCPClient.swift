import Foundation
import Network

/// Newline-delimited JSON client for kanata's TCP server on 127.0.0.1.
public final class KanataTCPClient: @unchecked Sendable {
    public enum Event: Sendable {
        case connected
        case message(KanataServerMessage)
        case disconnected
    }

    public static let host = "127.0.0.1"
    public static let retryInterval: TimeInterval = 0.25
    public static let slowRetryInterval: TimeInterval = 2
    /// kanata sleeps before it binds, so the first seconds after a start are retried quickly
    public static let fastRetryWindow: TimeInterval = 10

    private let queue = DispatchQueue(label: "io.jackyluong.barnata.kanata-tcp")
    private var connection: NWConnection?
    private var wantedPort: Int?
    private var buffer = Data()
    private var attemptsSince = Date.distantPast
    private var isReady = false
    private var isRetryScheduled = false
    private var wantsHello = true
    private var didLogSlowRetry = false

    /// Delivered on the main queue
    public var onEvent: (@Sendable (Event) -> Void)?

    public init() {}

    /// Idempotent. Safe to call on every status update; it repairs a connection that went away.
    public func connect(port: Int) {
        queue.async {
            if self.wantedPort != port {
                self.wantedPort = port
                self.wantsHello = true
                self.restartAttempts()
                self.teardown()
            }
            self.ensureConnection()
        }
    }

    public func disconnect() {
        queue.async {
            self.wantedPort = nil
            self.teardown()
        }
    }

    public func send(_ message: KanataClientMessage) {
        queue.async {
            guard self.isReady, let connection = self.connection else { return }
            connection.send(content: Data((message.line + "\n").utf8), completion: .contentProcessed { error in
                if let error { log.error("kanata tcp send failed: \(error.localizedDescription, privacy: .public)") }
            })
        }
    }

    /// Test hook: loses the socket with no retry pending, the state the old client wedged in
    func dropConnectionLeavingNoRetry() {
        queue.sync { teardown() }
    }

    // MARK: - Queue-confined internals

    /// The one place that decides whether to open a socket, so no path can leave the client idle
    private func ensureConnection() {
        guard wantedPort != nil, connection == nil, !isRetryScheduled else { return }
        open()
    }

    private func open() {
        guard let port = wantedPort,
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port))
        else { return }

        let options = NWProtocolTCP.Options()
        options.noDelay = true
        let connection = NWConnection(
            host: NWEndpoint.Host(KanataTCPClient.host),
            port: endpointPort,
            using: NWParameters(tls: nil, tcp: options)
        )
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection === connection else { return }
            switch state {
            case .ready: handleReady(connection)
            case .failed, .waiting, .cancelled: retry()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func handleReady(_ connection: NWConnection) {
        guard !isReady else { return }
        isReady = true
        buffer = Data()
        didLogSlowRetry = false
        emit(.connected)
        receive(on: connection)
        if wantsHello { send(.hello) }
        send(.requestLayerNames)
        send(.requestCurrentLayerName)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === connection else { return }
            if let data, !data.isEmpty {
                buffer.append(data)
                guard drainLines() else { return }
            }
            if isComplete || error != nil {
                retry()
                return
            }
            receive(on: connection)
        }
    }

    /// False when a line forced a reconnect, so the caller stops reading from the dead connection
    private func drainLines() -> Bool {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)

            if line.localizedCaseInsensitiveContains(KanataServerMessage.invalidMessageMarker) {
                log.notice("kanata rejected a message, reconnecting without Hello")
                wantsHello = false
                retry()
                return false
            }
            if let message = KanataServerMessage.decode(line: line) { emit(.message(message)) }
        }
        return true
    }

    private func retry() {
        guard wantedPort != nil, !isRetryScheduled else { return }

        if isReady {
            restartAttempts()
            emit(.disconnected)
        }
        teardown()

        let delay: TimeInterval
        if Date().timeIntervalSince(attemptsSince) < KanataTCPClient.fastRetryWindow {
            delay = KanataTCPClient.retryInterval
        } else {
            delay = KanataTCPClient.slowRetryInterval
            if !didLogSlowRetry {
                didLogSlowRetry = true
                log.notice("kanata is not answering on \(KanataTCPClient.host, privacy: .public), still retrying")
            }
        }

        isRetryScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            isRetryScheduled = false
            ensureConnection()
        }
    }

    private func restartAttempts() {
        attemptsSince = Date()
        didLogSlowRetry = false
    }

    private func teardown() {
        isReady = false
        guard let connection else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        self.connection = nil
    }

    private func emit(_ event: Event) {
        guard let onEvent else { return }
        DispatchQueue.main.async { onEvent(event) }
    }
}
