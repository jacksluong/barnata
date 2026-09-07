import Foundation

/// Appends child output to /Library/Logs/Barnata/<name>, rotating at a size cap.
/// Every call is serialized on the caller's queue by ProcessSupervisor.
public final class LogWriter: @unchecked Sendable {
    public static let maxBytes = 5 * 1024 * 1024
    public static let keptRotations = 3
    private static let directoryPermissions: NSNumber = 0o755
    private static let filePermissions: NSNumber = 0o644

    public let url: URL
    private let maxBytes: Int
    private let keptRotations: Int
    private var handle: FileHandle?

    public init(url: URL, maxBytes: Int = LogWriter.maxBytes, keptRotations: Int = LogWriter.keptRotations) {
        self.url = url
        self.maxBytes = maxBytes
        self.keptRotations = keptRotations
    }

    deinit { try? handle?.close() }

    public func write(_ data: Data) {
        guard !data.isEmpty else { return }
        do {
            var handle = try openHandle()
            // Rotate before writing, so the newest output is always in the file someone is tailing
            if try handle.offset() > 0, try handle.offset() + UInt64(data.count) > UInt64(maxBytes) {
                try rotate()
                handle = try openHandle()
            }
            try handle.write(contentsOf: data)
        } catch {
            log.error("cannot write \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func writeLine(_ text: String) {
        write(Data("\(text)\n".utf8))
    }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: LogWriter.directoryPermissions]
        )
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: LogWriter.filePermissions])
        }

        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return opened
    }

    private func rotate() throws {
        let fileManager = FileManager.default
        try? handle?.close()
        handle = nil

        try? fileManager.removeItem(at: rotationURL(keptRotations))
        for index in stride(from: keptRotations - 1, through: 0, by: -1) {
            let source = index == 0 ? url : rotationURL(index)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.removeItem(at: rotationURL(index + 1))
            try fileManager.moveItem(at: source, to: rotationURL(index + 1))
        }
    }

    private func rotationURL(_ index: Int) -> URL {
        url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).\(index)")
    }
}
