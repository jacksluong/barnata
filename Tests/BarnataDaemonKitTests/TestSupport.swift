import BarnataCore
import Foundation
import XCTest

@testable import BarnataDaemonKit

let callerUID: uid_t = 501
let otherUID: uid_t = 502

/// Answers file questions from a table instead of the disk
struct FakeFileInspector: FileInspecting {
    var files: [String: FileFacts]

    func facts(forPath path: String) -> FileFacts? { files[path] }
}

extension FileFacts {
    static func regularFile(ownedBy uid: uid_t = callerUID, worldReadable: Bool = false) -> FileFacts {
        FileFacts(isRegularFile: true, ownerUID: uid, isWorldReadable: worldReadable)
    }

    static func directory(ownedBy uid: uid_t = callerUID) -> FileFacts {
        FileFacts(isRegularFile: false, ownerUID: uid, isWorldReadable: true)
    }
}

/// Records scheduled work so tests can fire it instead of sleeping
final class ManualScheduler: Scheduler, @unchecked Sendable {
    struct Entry {
        var delay: TimeInterval
        var work: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var delays: [TimeInterval] {
        lock.withLock { entries.map(\.delay) }
    }

    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        lock.withLock { entries.append(Entry(delay: delay, work: work)) }
    }

    /// Runs and removes every pending entry
    func fireAll() {
        let pending = lock.withLock { defer { entries = [] }; return entries }
        pending.forEach { $0.work() }
    }
}

/// A Spawner that never touches a process, so the supervisor's state machine is testable
final class FakeSpawner: Spawner, @unchecked Sendable {
    private let lock = NSLock()
    private var nextPID: pid_t = 1000
    private var waiters: [pid_t: @Sendable (ExitReason) -> Void] = [:]

    private var recordedSpawns: [SpawnRequest] = []
    private var recordedSignals: [(signal: Int32, pid: pid_t)] = []
    var spawnError: SpawnError?
    /// When set, the child exits on the first signal, the way a well behaved process does
    var exitsOnSignal: Bool = false

    var spawnRequests: [SpawnRequest] { lock.withLock { recordedSpawns } }
    var signals: [(signal: Int32, pid: pid_t)] { lock.withLock { recordedSignals } }
    var lastPID: pid_t { lock.withLock { nextPID } }

    func spawn(_ request: SpawnRequest) throws -> SpawnedProcess {
        if let spawnError { throw spawnError }
        return lock.withLock {
            nextPID += 1
            recordedSpawns.append(request)
            return SpawnedProcess(pid: nextPID, responsibilityDisclaimed: true)
        }
    }

    func signal(_ signal: Int32, to pid: pid_t) {
        lock.withLock { recordedSignals.append((signal, pid)) }
        guard exitsOnSignal else { return }
        exit(pid: pid, reason: .exited(code: 0))
    }

    func wait(for pid: pid_t, completion: @escaping @Sendable (ExitReason) -> Void) {
        lock.withLock { waiters[pid] = completion }
    }

    func isRunning(_ pid: pid_t) -> Bool {
        lock.withLock { waiters[pid] != nil }
    }

    /// Delivers an exit to the supervisor, the way waitpid would
    func exit(pid: pid_t, reason: ExitReason) {
        let waiter = lock.withLock { waiters.removeValue(forKey: pid) }
        waiter?(reason)
    }

    func signalCount(_ signal: Int32) -> Int {
        lock.withLock { recordedSignals.filter { $0.signal == signal }.count }
    }
}

struct NoValidation: BinaryValidating {
    func validate(path: String, requirement: String) throws {}
}

func makeRequest(
    presetName: String = "Default",
    configPaths: [String] = ["/Users/test/.config/kanata/example.kbd"],
    extraArgs: [String] = [],
    autorestartOnCrash: Bool = false
) -> ValidatedStartRequest {
    ValidatedStartRequest(
        presetName: presetName,
        configPaths: configPaths,
        extraArgs: extraArgs,
        autorestartOnCrash: autorestartOnCrash,
        ownerUID: callerUID,
        arguments: ["-c", configPaths[0], "--no-wait"]
    )
}

func makeSupervisor(
    spawner: FakeSpawner,
    scheduler: Scheduler,
    terminationGrace: TimeInterval = 3,
    allocatePort: (@Sendable () -> Int)? = nil
) -> ProcessSupervisor {
    ProcessSupervisor(
        configuration: ProcessSupervisor.Configuration(
            executablePath: "/does/not/matter/kanata",
            requirement: nil,
            terminationGrace: terminationGrace,
            allocatePort: allocatePort
        ),
        spawner: spawner,
        validator: NoValidation(),
        logWriter: nil,
        scheduler: scheduler
    )
}

/// Hands out a fixed sequence of ports so a test can watch a restart pick a new one
final class PortSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int]

    init(_ values: [Int]) { self.values = values }

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? 0 : values.removeFirst()
    }
}
