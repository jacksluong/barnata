import Darwin
import Foundation
import XCTest

@testable import BarnataAppKit

/// Stands in for kanata's TCP server: answers RequestLayerNames, and can be stopped and rebound
private final class FakeKanataServer: @unchecked Sendable {
    private(set) var port: Int = 0
    private var listenerFD: Int32 = -1
    private var clientFDs: [Int32] = []
    private var isStopped = false
    private let lock = NSLock()

    /// Binds 127.0.0.1 on `port`, or on a free port when it is zero
    func start(on port: Int = 0) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw Failure.bind(errno)
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) { pointer in
            _ = pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }

        lock.withLock {
            listenerFD = fd
            isStopped = false
        }
        self.port = Int(UInt16(bigEndian: assigned.sin_port))
        Thread.detachNewThread { [weak self] in self?.acceptLoop(fd) }
    }

    /// Closes the accepted sockets too, the way a killed kanata does
    func stop() {
        let (listener, clients): (Int32, [Int32]) = lock.withLock {
            isStopped = true
            let current = listenerFD
            let open = clientFDs
            listenerFD = -1
            clientFDs = []
            return (current, open)
        }
        if listener >= 0 { close(listener) }
        clients.forEach { close($0) }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            guard !lock.withLock({ isStopped }) else {
                close(client)
                return
            }
            lock.withLock { clientFDs.append(client) }
            Thread.detachNewThread { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else {
                lock.withLock {
                    guard let index = clientFDs.firstIndex(of: client) else { return }
                    clientFDs.remove(at: index)
                    close(client)
                }
                return
            }
            guard String(decoding: buffer[0..<count], as: UTF8.self).contains("RequestLayerNames") else { continue }
            let reply = "{\"LayerNames\":{\"names\":[\"base\",\"typing\"]}}\n"
            _ = Array(reply.utf8).withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count) }
        }
    }

    enum Failure: Error {
        case socket(Int32)
        case bind(Int32)
    }
}

final class KanataTCPClientTests: XCTestCase {
    private var server = FakeKanataServer()
    private var client = KanataTCPClient()

    override func setUp() {
        server = FakeKanataServer()
        client = KanataTCPClient()
    }

    override func tearDown() {
        client.disconnect()
        server.stop()
    }

    private func expectLayerNames(_ description: String) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.assertForOverFulfill = false
        client.onEvent = { event in
            if case .message(.layerNames) = event { expectation.fulfill() }
        }
        return expectation
    }

    func testItConnectsOnceTheServerAppears() throws {
        // Take the port first so the client has something to aim at while nothing listens
        try server.start()
        let port = server.port
        server.stop()

        let layers = expectLayerNames("layer names after the server binds")
        client.connect(port: port)

        // kanata sleeps before binding, so the client has to keep retrying
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { try? self.server.start(on: port) }
        wait(for: [layers], timeout: 20)
    }

    /// The bug: after a few stop and start rounds the client stopped reconnecting for good
    func testItReconnectsAcrossRepeatedStopAndStartRounds() throws {
        try server.start()
        let port = server.port
        client.connect(port: port)
        wait(for: [expectLayerNames("first connect")], timeout: 20)

        for round in 1...5 {
            client.disconnect()
            server.stop()

            server = FakeKanataServer()
            try server.start(on: port)
            let layers = expectLayerNames("layer names in round \(round)")
            client.connect(port: port)
            wait(for: [layers], timeout: 20)
        }
    }

    /// Every status update calls connect, which must never wedge a working connection
    func testRepeatedConnectCallsAreIdempotent() throws {
        try server.start()
        client.connect(port: server.port)
        wait(for: [expectLayerNames("first connect")], timeout: 20)

        for _ in 1...10 { client.connect(port: server.port) }

        let layers = expectLayerNames("layer names after redundant connects")
        client.send(.requestLayerNames)
        wait(for: [layers], timeout: 20)
    }

    /// The wedge itself: a client with no socket and no retry pending must heal on the next connect
    func testConnectRepairsAClientThatLostItsConnectionSilently() throws {
        try server.start()
        let port = server.port
        client.connect(port: port)
        wait(for: [expectLayerNames("first connect")], timeout: 20)

        client.dropConnectionLeavingNoRetry()

        let layers = expectLayerNames("layer names after the repair")
        client.connect(port: port)
        wait(for: [layers], timeout: 20)
    }

    /// A server that dies without the app noticing must be picked up again
    func testItRecoversWhenTheServerDropsWithoutADisconnectCall() throws {
        try server.start()
        let port = server.port
        client.connect(port: port)
        wait(for: [expectLayerNames("first connect")], timeout: 20)

        server.stop()
        server = FakeKanataServer()
        let layers = expectLayerNames("layer names after the server came back")
        try server.start(on: port)
        wait(for: [layers], timeout: 20)
    }
}
