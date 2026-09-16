import Foundation
import Network

/// Newline-delimited JSON client for kanata's TCP server on 127.0.0.1.
public final class KanataTCPClient: @unchecked Sendable {
    public enum Event: Sendable {
        case connected
        case message(KanataServerMessage)
        case disconnected
        case gaveUp
    }

    public static let host = "127.0.0.1"
    public static let retryInterval: TimeInterval = 0.25
    public static let retryLimit: TimeInterval = 10

    private let queue = DispatchQueue(label: "io.jackyluong.barnata.kanata-tcp")
    private var connection: NWConnection?
    private var port: Int?
    private var buffer = Data()
    private var deadline = Date.distantPast
    private var isReady = false
    private var isStopped = true
    private var isRetryScheduled = false
    private var wantsHello = true

    /// Delivered on the main queue
    public var onEvent: (@Sendable (Event) -> Void)?

    public init() {}

    public func connect(port: Int) {
        queue.async {
            guard self.port != port || self.isStopped else { return }
            self.teardown()
            self.isStopped = false
            self.port = port
            self.wantsHello = true
            self.deadline = Date().addingTimeInterval(KanataTCPClient.retryLimit)
            self.open()
        }
    }

    public func disconnect() {
        queue.async {
            self.isStopped = true
            self.port = nil
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

    // MARK: - Queue-confined internals

    private func open() {
        guard !isStopped, connection == nil, let port,
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
            guard let self else { return }
            switch state {
            case .ready: handleReady(connection)
            case .failed, .waiting, .cancelled: scheduleRetry()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func handleReady(_ connection: NWConnection) {
        guard self.connection === connection, !isReady else { return }
        isReady = true
        buffer = Data()
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
                scheduleRetry()
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
                deadline = Date().addingTimeInterval(KanataTCPClient.retryLimit)
                scheduleRetry()
                return false
            }
            if let message = KanataServerMessage.decode(line: line) { emit(.message(message)) }
        }
        return true
    }

    private func scheduleRetry() {
        guard !isStopped, !isRetryScheduled else { return }

        if isReady {
            // A live connection dropped, so the retry window starts over
            deadline = Date().addingTimeInterval(KanataTCPClient.retryLimit)
            emit(.disconnected)
        }
        teardown()

        guard Date() < deadline else {
            log.error("gave up connecting to kanata on \(KanataTCPClient.host, privacy: .public)")
            isStopped = true
            emit(.gaveUp)
            return
        }

        isRetryScheduled = true
        queue.asyncAfter(deadline: .now() + KanataTCPClient.retryInterval) { [weak self] in
            guard let self else { return }
            isRetryScheduled = false
            open()
        }
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
