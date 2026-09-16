import Foundation

/// Watches config.toml and the directory holding it, so atomic saves by an editor still fire.
public final class ConfigWatcher: @unchecked Sendable {
    public static let coalesceInterval: TimeInterval = 0.15

    private let url: URL
    private let queue = DispatchQueue(label: "io.jackyluong.barnata.config-watcher")
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?
    private var ignoredDate: Date?
    private var isStopped = true

    /// Delivered on the main queue
    public var onChange: (@Sendable () -> Void)?

    public init(url: URL) {
        self.url = url
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
    }

    public func start() {
        queue.async {
            guard self.isStopped else { return }
            self.isStopped = false
            self.watchDirectory()
            self.watchFile()
        }
    }

    public func stop() {
        queue.async {
            self.isStopped = true
            self.pendingWork?.cancel()
            self.pendingWork = nil
            self.fileSource?.cancel()
            self.fileSource = nil
            self.directorySource?.cancel()
            self.directorySource = nil
        }
    }

    /// Suppresses the single event caused by the app's own write
    public func ignoreChange(modifiedAt date: Date?) {
        queue.async { self.ignoredDate = date }
    }

    // MARK: - Queue-confined internals

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                // The editor replaced the file, so the old descriptor now points at nothing
                watchFile()
            }
            scheduleNotify()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileSource = source
    }

    private func watchDirectory() {
        let directory = url.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if fileSource == nil { watchFile() }
            scheduleNotify()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// Editors emit several events per save, so collapse them into one reload
    private func scheduleNotify() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.notifyIfChanged() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + ConfigWatcher.coalesceInterval, execute: work)
    }

    private func notifyIfChanged() {
        pendingWork = nil
        guard !isStopped else { return }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        if let ignoredDate, let modified, ignoredDate == modified {
            self.ignoredDate = nil
            return
        }
        ignoredDate = nil

        guard let onChange else { return }
        DispatchQueue.main.async(execute: onChange)
    }
}
