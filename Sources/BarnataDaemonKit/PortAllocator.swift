import Foundation

/// Picks the loopback port kanata listens on. The unprivileged side never supplies one,
/// so nothing in the config file can point the daemon at a port the user chose.
public enum PortAllocator {
    public static let preferredPort = 5829
    public static let range = 1024...65535
    public static let scanLength = 32

    /// `preferred` when it is free, then the next free port above it, then whatever the
    /// kernel hands out. The probe socket is closed before kanata binds, so a port can
    /// still be taken in between; kanata then fails to start and reports the bind error.
    public static func allocate(preferred: Int = preferredPort) -> Int {
        let start = Swift.max(preferred, range.lowerBound)
        for port in start..<Swift.min(start + scanLength, range.upperBound + 1) {
            if let bound = bindProbe(port) { return bound }
        }
        // Port 0 asks the kernel for a free one, which lands in the ephemeral range
        return bindProbe(0) ?? preferredPort
    }

    public static func isAvailable(_ port: Int) -> Bool {
        bindProbe(port) != nil
    }

    /// Binds 127.0.0.1:port, reads the port back, and closes the socket.
    /// Returns nil when the bind failed, which is what makes this an availability test.
    private static func bindProbe(_ port: Int) -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
