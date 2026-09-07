import XCTest

@testable import BarnataDaemonKit

final class BackoffPolicyTests: XCTestCase {
    func testDelaysGrowAndThenHold() {
        let policy = BackoffPolicy()
        XCTAssertEqual((1...6).map(policy.delay(forCrash:)), [1, 2, 4, 8, 30, 30])
    }

    func testGivesUpOnTheSixthCrashInsideTheWindow() {
        var policy = BackoffPolicy()
        let start = Date()
        let decisions = (0..<6).map { policy.recordCrash(at: start.addingTimeInterval(Double($0) * 10)) }

        XCTAssertEqual(
            decisions,
            [.restart(after: 1), .restart(after: 2), .restart(after: 4), .restart(after: 8), .restart(after: 30), .giveUp]
        )
    }

    func testTheCounterResetsAfterTheWindow() {
        var policy = BackoffPolicy()
        let start = Date()
        for offset in 0..<5 {
            _ = policy.recordCrash(at: start.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(policy.restartCount, 5)

        let afterWindow = policy.recordCrash(at: start.addingTimeInterval(policy.window))
        XCTAssertEqual(afterWindow, .restart(after: 1))
        XCTAssertEqual(policy.restartCount, 1)
    }

    func testCrashesSpreadPastTheWindowNeverGiveUp() {
        var policy = BackoffPolicy()
        let start = Date()
        for offset in 0..<20 {
            let decision = policy.recordCrash(at: start.addingTimeInterval(Double(offset) * 130))
            XCTAssertEqual(decision, .restart(after: 1), "crash \(offset)")
        }
    }

    func testResetClearsTheCounter() {
        var policy = BackoffPolicy()
        _ = policy.recordCrash()
        policy.reset()
        XCTAssertEqual(policy.restartCount, 0)
        XCTAssertEqual(policy.recordCrash(), .restart(after: 1))
    }
}
