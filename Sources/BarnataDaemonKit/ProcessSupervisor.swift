import BarnataCore
import Foundation

public struct SupervisorSnapshot: Sendable, Equatable {
    public var state: KanataState = .idle
    public var pid: pid_t?
    public var presetName: String?
    public var configPaths: [String] = []
    public var tcpPort: Int?
    public var ownerUID: uid_t?
    public var lastExitCode: Int32?
    public var lastError: String?
    public var restartCount: Int = 0
}

/// Starts, stops, and restarts one child process. All state is confined to `queue`.
public final class ProcessSupervisor: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var executablePath: String
        /// Code signing requirement checked before every spawn, nil skips the check
        public var requirement: String?
        public var terminationGrace: TimeInterval
        public var stderrTailLines: Int
        public var backoff: BackoffPolicy

        public init(
            executablePath: String,
            requirement: String?,
            terminationGrace: TimeInterval = 3,
            stderrTailLines: Int = 20,
            backoff: BackoffPolicy = BackoffPolicy()
        ) {
            self.executablePath = executablePath
            self.requirement = requirement
            self.terminationGrace = terminationGrace
            self.stderrTailLines = stderrTailLines
            self.backoff = backoff
        }
    }

    private let configuration: Configuration
    private let spawner: Spawner
    private let validator: BinaryValidating
    private let logWriter: LogWriter?
    private let scheduler: Scheduler
    private let queue: DispatchQueue
    private let onChange: @Sendable (SupervisorSnapshot) -> Void

    private var backoff: BackoffPolicy
    private var state: KanataState = .idle
    private var currentPID: pid_t?
    private var request: ValidatedStartRequest?
    private var lastExitCode: Int32?
    private var lastError: String?
    private var stoppingOnPurpose = false
    private var pendingStart: ValidatedStartRequest?
    private var pumps: [DispatchSourceRead] = []
    private var stderrTail: [String] = []
    private var stderrPartial = ""

    public init(
        configuration: Configuration,
        spawner: Spawner,
        validator: BinaryValidating = SignatureCheck(),
        logWriter: LogWriter? = nil,
        scheduler: Scheduler = QueueScheduler(),
        queue: DispatchQueue = DispatchQueue(label: "io.jackyluong.barnata.supervisor"),
        onChange: @escaping @Sendable (SupervisorSnapshot) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.spawner = spawner
        self.validator = validator
        self.logWriter = logWriter
        self.scheduler = scheduler
        self.queue = queue
        self.onChange = onChange
        self.backoff = configuration.backoff
    }

    public var snapshot: SupervisorSnapshot { queue.sync { currentSnapshot() } }

    public var isBusy: Bool { queue.sync { currentPID != nil || pendingStart != nil } }

    @discardableResult
    public func start(_ request: ValidatedStartRequest) -> CommandResult {
        queue.sync {
            guard currentPID != nil else { return spawn(request) }
            pendingStart = request
            beginStop()
            return CommandResult(ok: true, message: "stopping the running process first")
        }
    }

    @discardableResult
    public func stop() -> CommandResult {
        queue.sync {
            pendingStart = nil
            guard currentPID != nil else {
                if state != .idle { transition(to: .idle) }
                return CommandResult(ok: true, message: "not running")
            }
            beginStop()
            return .success
        }
    }

    @discardableResult
    public func restart() -> CommandResult {
        queue.sync {
            guard let request else { return .failure("no preset has been started yet") }
            guard currentPID != nil else { return spawn(request) }
            pendingStart = request
            beginStop()
            return .success
        }
    }

    /// SIGTERM without waiting, for daemon exit
    public func terminateNow() {
        queue.sync {
            pendingStart = nil
            guard let pid = currentPID else { return }
            stoppingOnPurpose = true
            spawner.signal(SIGTERM, to: pid)
        }
    }

    // MARK: - Queue-confined internals

    private func spawn(_ request: ValidatedStartRequest) -> CommandResult {
        if let requirement = configuration.requirement {
            do {
                try validator.validate(path: configuration.executablePath, requirement: requirement)
            } catch {
                let message = "refusing to start: \(error)"
                log.error("\(message, privacy: .public)")
                self.request = request
                lastError = message
                transition(to: .crashed)
                return .failure(message)
            }
        }

        self.request = request
        stderrTail = []
        stderrPartial = ""
        transition(to: .starting)

        let spawnRequest = SpawnRequest(
            executablePath: configuration.executablePath,
            arguments: request.arguments,
            environment: SpawnRequest.daemonChildEnvironment
        )

        let child: SpawnedProcess
        do {
            child = try spawner.spawn(spawnRequest)
        } catch {
            let message = "\(error)"
            log.error("\(message, privacy: .public)")
            lastError = message
            transition(to: .crashed)
            return .failure(message)
        }

        currentPID = child.pid
        lastExitCode = nil
        lastError = nil
        logWriter?.writeLine(
            "--- barnata started \(configuration.executablePath) pid \(child.pid) "
                + "responsibilityDisclaimed=\(child.responsibilityDisclaimed) ---"
        )
        pump(child.standardOutput, isStandardError: false)
        pump(child.standardError, isStandardError: true)

        spawner.wait(for: child.pid) { [weak self] reason in
            guard let self else { return }
            queue.async { self.handleExit(pid: child.pid, reason: reason) }
        }

        transition(to: .running)
        return .success
    }

    private func beginStop() {
        guard let pid = currentPID else { return }
        stoppingOnPurpose = true
        transition(to: .stopping)
        spawner.signal(SIGTERM, to: pid)
        scheduler.schedule(after: configuration.terminationGrace) { [weak self] in
            guard let self else { return }
            queue.async {
                guard self.currentPID == pid, self.state == .stopping else { return }
                log.error("\(self.configuration.executablePath, privacy: .public) ignored SIGTERM, sending SIGKILL")
                self.spawner.signal(SIGKILL, to: pid)
            }
        }
    }

    private func handleExit(pid: pid_t, reason: ExitReason) {
        guard currentPID == pid else { return }
        currentPID = nil
        cancelPumps()
        lastExitCode = reason.code
        logWriter?.writeLine("--- barnata pid \(pid) exited \(reason) ---")

        let wasIntentional = stoppingOnPurpose
        stoppingOnPurpose = false

        if wasIntentional || !reason.isCrash {
            backoff.reset()
            lastError = nil
            transition(to: .idle)
        } else {
            lastError = stderrTail.isEmpty ? nil : stderrTail.joined(separator: "\n")
            transition(to: .crashed)
        }

        if let next = pendingStart {
            pendingStart = nil
            _ = spawn(next)
            return
        }

        guard !wasIntentional, reason.isCrash, let request, request.autorestartOnCrash else { return }
        switch backoff.recordCrash() {
        case .restart(let delay):
            log.notice("restarting after a crash in \(delay, privacy: .public) s")
            scheduler.schedule(after: delay) { [weak self] in
                guard let self else { return }
                queue.async {
                    guard self.currentPID == nil, self.state == .crashed else { return }
                    _ = self.spawn(request)
                }
            }
        case .giveUp:
            log.error("giving up after \(self.backoff.maxRestarts) restarts inside \(self.backoff.window, privacy: .public) s")
            lastError = ((lastError.map { $0 + "\n" }) ?? "")
                + "gave up after \(backoff.maxRestarts) restarts inside \(Int(backoff.window)) seconds"
            transition(to: .crashed)
        }
    }

    private func pump(_ fileDescriptor: Int32, isStandardError: Bool) {
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            let count = read(fileDescriptor, &buffer, buffer.count)
            guard count > 0 else {
                source.cancel()
                return
            }
            let data = Data(buffer[0..<count])
            logWriter?.write(data)
            if isStandardError { appendToTail(String(decoding: data, as: UTF8.self)) }
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        pumps.append(source)
    }

    private func cancelPumps() {
        pumps.forEach { $0.cancel() }
        pumps = []
    }

    private func appendToTail(_ text: String) {
        stderrPartial += text
        var lines = stderrPartial.components(separatedBy: "\n")
        stderrPartial = lines.removeLast()
        stderrTail.append(contentsOf: lines)
        if stderrTail.count > configuration.stderrTailLines {
            stderrTail.removeFirst(stderrTail.count - configuration.stderrTailLines)
        }
    }

    private func transition(to newState: KanataState) {
        state = newState
        onChange(currentSnapshot())
    }

    private func currentSnapshot() -> SupervisorSnapshot {
        SupervisorSnapshot(
            state: state,
            pid: currentPID,
            presetName: request?.presetName,
            configPaths: request?.configPaths ?? [],
            tcpPort: request?.tcpPort,
            ownerUID: request?.ownerUID,
            lastExitCode: lastExitCode,
            lastError: lastError,
            restartCount: backoff.restartCount
        )
    }
}
