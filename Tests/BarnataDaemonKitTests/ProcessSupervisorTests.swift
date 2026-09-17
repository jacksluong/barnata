import BarnataCore
import XCTest

@testable import BarnataDaemonKit

final class ProcessSupervisorTests: XCTestCase {
    private var spawner: FakeSpawner!
    private var scheduler: ManualScheduler!
    private var supervisor: ProcessSupervisor!

    override func setUp() {
        super.setUp()
        spawner = FakeSpawner()
        scheduler = ManualScheduler()
        supervisor = makeSupervisor(spawner: spawner, scheduler: scheduler)
    }

    /// The supervisor handles exits on its own queue, and reading `snapshot` waits for that queue
    private func deliverExit(_ reason: ExitReason, pid: pid_t? = nil) {
        spawner.exit(pid: pid ?? spawner.lastPID, reason: reason)
        _ = supervisor.snapshot
    }

    private func fireTimers() {
        scheduler.fireAll()
        _ = supervisor.snapshot
    }

    func testStartSpawnsWithTheValidatedArgumentsAndTheFixedEnvironment() {
        let request = makeRequest()
        XCTAssertEqual(supervisor.start(request), .success)

        XCTAssertEqual(spawner.spawnRequests.count, 1)
        XCTAssertEqual(spawner.spawnRequests[0].arguments, request.arguments)
        XCTAssertEqual(spawner.spawnRequests[0].environment, SpawnRequest.daemonChildEnvironment)
        XCTAssertEqual(supervisor.snapshot.state, .running)
        XCTAssertEqual(supervisor.snapshot.ownerUID, callerUID)
    }

    func testTheListenFlagComesFromTheAllocatorNotTheRequest() {
        let ports = PortSequence([5829, 5830])
        let supervisor = makeSupervisor(
            spawner: spawner,
            scheduler: scheduler,
            allocatePort: { ports.next() }
        )
        let request = makeRequest()

        supervisor.start(request)
        XCTAssertEqual(spawner.spawnRequests[0].arguments, request.arguments + ["-p", "127.0.0.1:5829"])
        XCTAssertEqual(supervisor.snapshot.tcpPort, 5829)

        let first = spawner.lastPID
        supervisor.restart()
        spawner.exit(pid: first, reason: .signaled(signal: SIGTERM))
        _ = supervisor.snapshot

        XCTAssertEqual(spawner.spawnRequests[1].arguments, request.arguments + ["-p", "127.0.0.1:5830"])
        XCTAssertEqual(supervisor.snapshot.tcpPort, 5830)
    }

    func testNoAllocatorMeansNoListenFlag() {
        let request = makeRequest()
        supervisor.start(request)
        XCTAssertEqual(spawner.spawnRequests[0].arguments, request.arguments)
        XCTAssertNil(supervisor.snapshot.tcpPort)
    }

    func testExitZeroLeavesTheSupervisorIdle() {
        supervisor.start(makeRequest())
        deliverExit(.exited(code: 0))

        let snapshot = supervisor.snapshot
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertEqual(snapshot.lastExitCode, 0)
        XCTAssertNil(snapshot.pid)
    }

    func testNonZeroExitIsACrash() {
        supervisor.start(makeRequest())
        deliverExit(.exited(code: 1))

        let snapshot = supervisor.snapshot
        XCTAssertEqual(snapshot.state, .crashed)
        XCTAssertEqual(snapshot.lastExitCode, 1)
    }

    func testAKilledChildIsACrash() {
        supervisor.start(makeRequest())
        deliverExit(.signaled(signal: SIGKILL))

        XCTAssertEqual(supervisor.snapshot.state, .crashed)
    }

    func testACrashSchedulesARestartWhenAutorestartIsOn() {
        supervisor.start(makeRequest(autorestartOnCrash: true))
        deliverExit(.exited(code: 1))

        XCTAssertEqual(scheduler.delays, [1])
        XCTAssertEqual(spawner.spawnRequests.count, 1)

        fireTimers()
        XCTAssertEqual(spawner.spawnRequests.count, 2)
        XCTAssertEqual(supervisor.snapshot.state, .running)
    }

    func testACrashDoesNotRestartWhenAutorestartIsOff() {
        supervisor.start(makeRequest(autorestartOnCrash: false))
        deliverExit(.exited(code: 1))

        XCTAssertEqual(scheduler.delays, [])
        fireTimers()
        XCTAssertEqual(spawner.spawnRequests.count, 1)
    }

    func testRepeatedCrashesBackOffAndThenGiveUp() {
        supervisor.start(makeRequest(autorestartOnCrash: true))
        for _ in 0..<6 {
            deliverExit(.exited(code: 1))
            fireTimers()
        }

        XCTAssertEqual(scheduler.delays, [])
        XCTAssertEqual(supervisor.snapshot.state, .crashed)
        XCTAssertEqual(spawner.spawnRequests.count, 6)
        XCTAssertTrue(supervisor.snapshot.lastError?.contains("gave up after 5 restarts") == true)
    }

    func testStopSendsSIGTERMAndThenSIGKILLAfterTheGracePeriod() {
        supervisor.start(makeRequest())
        let pid = spawner.lastPID

        XCTAssertEqual(supervisor.stop(), .success)
        XCTAssertEqual(spawner.signals.map(\.signal), [SIGTERM])
        XCTAssertEqual(supervisor.snapshot.state, .stopping)
        XCTAssertEqual(scheduler.delays, [3])

        fireTimers()
        XCTAssertEqual(spawner.signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertEqual(spawner.signals.map(\.pid), [pid, pid])
    }

    func testAChildThatHonoursSIGTERMIsNeverKilled() {
        supervisor.start(makeRequest())
        supervisor.stop()
        deliverExit(.signaled(signal: SIGTERM))

        fireTimers()
        XCTAssertEqual(spawner.signalCount(SIGKILL), 0)
        XCTAssertEqual(supervisor.snapshot.state, .idle)
    }

    func testAnIntentionalStopIsNotTreatedAsACrash() {
        supervisor.start(makeRequest(autorestartOnCrash: true))
        supervisor.stop()
        deliverExit(.exited(code: 1))

        XCTAssertEqual(supervisor.snapshot.state, .idle)
        XCTAssertEqual(scheduler.delays, [3], "only the SIGKILL timer, no restart")
    }

    func testStartingWhileRunningStopsTheCurrentChildFirst() {
        supervisor.start(makeRequest(presetName: "First"))
        let first = spawner.lastPID

        supervisor.start(makeRequest(presetName: "Second"))
        XCTAssertEqual(spawner.signals.map(\.signal), [SIGTERM])
        XCTAssertEqual(spawner.spawnRequests.count, 1, "the second child waits for the first to exit")

        deliverExit(.signaled(signal: SIGTERM), pid: first)
        XCTAssertEqual(spawner.spawnRequests.count, 2)
        XCTAssertEqual(supervisor.snapshot.presetName, "Second")
        XCTAssertEqual(supervisor.snapshot.state, .running)
    }

    func testRestartReusesTheLastRequest() {
        supervisor.start(makeRequest(presetName: "First"))
        let first = spawner.lastPID

        XCTAssertEqual(supervisor.restart(), .success)
        deliverExit(.signaled(signal: SIGTERM), pid: first)

        XCTAssertEqual(spawner.spawnRequests.count, 2)
        XCTAssertEqual(supervisor.snapshot.presetName, "First")
    }

    func testRestartBeforeAnyStartFails() {
        let result = supervisor.restart()
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.message, "no preset has been started yet")
    }

    /// Daemon exit used to send SIGTERM and leave, orphaning a kanata that ignores it
    func testTerminateNowKillsAChildThatIgnoresSIGTERM() {
        supervisor.start(makeRequest())
        let pid = spawner.lastPID

        supervisor.terminateNow(grace: 0.1)

        XCTAssertEqual(spawner.signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertEqual(spawner.signals.map(\.pid), [pid, pid])
    }

    func testTerminateNowSendsNoSIGKILLWhenTheChildGoesQuietly() {
        supervisor.start(makeRequest())
        spawner.exitsOnSignal = true

        supervisor.terminateNow(grace: 1)

        XCTAssertEqual(spawner.signals.map(\.signal), [SIGTERM])
    }

    func testStopWhenNothingRunsSucceeds() {
        let result = supervisor.stop()
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "not running")
    }

    func testAFailedSpawnLeavesTheSupervisorCrashed() {
        spawner.spawnError = SpawnError(description: "posix_spawn failed")
        let result = supervisor.start(makeRequest())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(supervisor.snapshot.state, .crashed)
        XCTAssertEqual(supervisor.snapshot.lastError, "posix_spawn failed")
    }

    func testAFailedSignatureCheckRefusesToSpawn() {
        let strictSupervisor = ProcessSupervisor(
            configuration: ProcessSupervisor.Configuration(
                executablePath: "/does/not/matter/kanata",
                requirement: "identifier \"io.jackyluong.barnata.kanata\""
            ),
            spawner: spawner,
            validator: RejectingValidator(),
            scheduler: scheduler
        )

        let result = strictSupervisor.start(makeRequest())
        XCTAssertFalse(result.ok)
        XCTAssertEqual(spawner.spawnRequests.count, 0)
        XCTAssertEqual(strictSupervisor.snapshot.state, .crashed)
    }
}

private struct RejectingValidator: BinaryValidating {
    func validate(path: String, requirement: String) throws {
        throw SignatureError(path: path, reason: "unsigned")
    }
}
