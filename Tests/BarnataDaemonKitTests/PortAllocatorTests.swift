import Foundation
import XCTest

@testable import BarnataDaemonKit

final class PortAllocatorTests: XCTestCase {
    func testThePreferredPortIsUsedWhenItIsFree() throws {
        let listener = try LoopbackListener()
        let free = listener.port
        listener.close()

        XCTAssertEqual(PortAllocator.allocate(preferred: free), free)
    }

    func testAPreferredPortBelowTheRangeIsRaisedIntoIt() {
        XCTAssertTrue(PortAllocator.range.contains(PortAllocator.allocate(preferred: 80)))
    }

    func testAnOccupiedPortIsSkipped() throws {
        let listener = try LoopbackListener()
        defer { listener.close() }

        XCTAssertFalse(PortAllocator.isAvailable(listener.port))
        let allocated = PortAllocator.allocate(preferred: listener.port)
        XCTAssertNotEqual(allocated, listener.port)
        XCTAssertGreaterThan(allocated, listener.port)
    }

    func testAFreePortIsReportedAvailable() throws {
        let listener = try LoopbackListener()
        let port = listener.port
        listener.close()
        XCTAssertTrue(PortAllocator.isAvailable(port))
    }

    func testAllocatedPortsAreInRange() {
        let port = PortAllocator.allocate()
        XCTAssertTrue(PortAllocator.range.contains(port), "\(port)")
    }
}

/// Holds a real loopback port open so the allocator has something to collide with
private final class LoopbackListener {
    let descriptor: Int32
    let port: Int

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestError.socket }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            Darwin.close(fd)
            throw TestError.bind
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }

        descriptor = fd
        port = Int(UInt16(bigEndian: assigned.sin_port))
    }

    func close() { Darwin.close(descriptor) }

    enum TestError: Error { case socket, bind }
}
