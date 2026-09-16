import BarnataCore
import Foundation
import XCTest

@testable import BarnataDaemonKit

/// The daemon's real listener reads `snapshot` from inside `onChange`, which deadlocked the
/// supervisor's queue until notifications were moved off it.
final class SupervisorNotificationTests: XCTestCase {
    private func supervisor(
        spawner: FakeSpawner,
        scheduler: Scheduler,
        onChange: @escaping @Sendable (SupervisorSnapshot) -> Void
    ) -> ProcessSupervisor {
        ProcessSupervisor(
            configuration: ProcessSupervisor.Configuration(
                executablePath: "/does/not/matter/kanata",
                requirement: nil
            ),
            spawner: spawner,
            validator: NoValidation(),
            logWriter: nil,
            scheduler: scheduler,
            onChange: onChange
        )
    }

    func testAListenerMayReadTheSnapshotItWasHandedAndTheLiveOne() {
        let spawner = FakeSpawner()
        let scheduler = ManualScheduler()
        let seen = Reported()

        let holder = SupervisorHolder()
        let subject = supervisor(spawner: spawner, scheduler: scheduler) { snapshot in
            // Re-entering the supervisor from a notification must not deadlock
            _ = holder.supervisor?.snapshot
            _ = holder.supervisor?.isBusy
            seen.append(snapshot.state)
        }
        holder.supervisor = subject

        subject.start(makeRequest())
        XCTAssertTrue(seen.waitForStates([.starting, .running], timeout: 2), "saw \(seen.states)")

        spawner.exit(pid: spawner.lastPID, reason: .exited(code: 0))
        XCTAssertTrue(seen.waitForStates([.starting, .running, .idle], timeout: 2), "saw \(seen.states)")
    }

    func testNotificationsArriveInTransitionOrder() {
        let spawner = FakeSpawner()
        let seen = Reported()
        let subject = supervisor(spawner: spawner, scheduler: ManualScheduler()) { seen.append($0.state) }

        subject.start(makeRequest())
        spawner.exit(pid: spawner.lastPID, reason: .exited(code: 1))

        XCTAssertTrue(seen.waitForStates([.starting, .running, .crashed], timeout: 2), "saw \(seen.states)")
    }
}

/// Collects the states a listener was told about
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [KanataState] = []

    var states: [KanataState] { lock.withLock { recorded } }

    func append(_ state: KanataState) {
        lock.withLock { recorded.append(state) }
    }

    /// Notifications are asynchronous, so poll rather than assert immediately
    func waitForStates(_ expected: [KanataState], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if states == expected { return true }
            usleep(5_000)
        }
        return states == expected
    }
}

/// Breaks the chicken-and-egg between the supervisor and a listener that reads it back
private final class SupervisorHolder: @unchecked Sendable {
    weak var supervisor: ProcessSupervisor?
}
