import Foundation
import XCTest

@testable import BarnataAppKit

final class LaunchStateTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "io.jackyluong.barnata.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstLaunchResumesNothing() {
        let state = LaunchState(defaults: defaults)
        XCTAssertNil(state.presetToResume(currentVersion: "16"))
    }

    func testSameVersionResumesNothing() {
        let state = LaunchState(defaults: defaults)
        state.recordLaunch(version: "16")
        state.recordRunningPreset("Default")
        XCTAssertNil(state.presetToResume(currentVersion: "16"))
    }

    func testNewVersionResumesTheRecordedPreset() {
        let state = LaunchState(defaults: defaults)
        state.recordLaunch(version: "16")
        state.recordRunningPreset("Default")
        XCTAssertEqual(state.presetToResume(currentVersion: "17"), "Default")
    }

    func testStoppingKanataLeavesNothingToResume() {
        let state = LaunchState(defaults: defaults)
        state.recordLaunch(version: "16")
        state.recordRunningPreset("Default")
        state.recordRunningPreset(nil)
        XCTAssertNil(state.presetToResume(currentVersion: "17"))
    }

    func testRecordingALaunchClosesTheUpgradeWindow() {
        let state = LaunchState(defaults: defaults)
        state.recordLaunch(version: "16")
        state.recordRunningPreset("Default")
        state.recordLaunch(version: "17")
        XCTAssertNil(state.presetToResume(currentVersion: "17"))
    }
}
