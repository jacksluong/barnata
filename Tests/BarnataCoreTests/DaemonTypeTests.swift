import Foundation
import XCTest

@testable import BarnataCore

final class DaemonTypeTests: XCTestCase {
    func testStartRequestSurvivesAnEnvelopeRoundTrip() throws {
        let request = StartRequest(
            presetName: "Default",
            configPath: "/Users/test/.config/kanata/example.kbd",
            extraArgs: ["--debug"],
            autorestartOnCrash: true
        )
        XCTAssertEqual(try Envelope.decode(StartRequest.self, from: Envelope.encode(request)), request)
    }

    func testDaemonStatusSurvivesAnEnvelopeRoundTrip() throws {
        let status = DaemonStatus(
            daemonVersion: "0.1.0",
            kanataVersion: "1.12.0",
            state: .running,
            pid: 4242,
            presetName: "Default",
            configPath: "/tmp/a.kbd",
            tcpPort: 5829,
            restartCount: 2,
            driver: DriverStatus(installed: true, version: "6.8.0", requiredVersion: "6.8.0", activated: true)
        )
        XCTAssertEqual(try Envelope.decode(DaemonStatus.self, from: Envelope.encode(status)), status)
    }

    func testDecodingAMismatchedPayloadThrows() throws {
        let data = try Envelope.encode(CommandResult(ok: true))
        XCTAssertThrowsError(try Envelope.decode(StartRequest.self, from: data))
    }

    func testPresetBuildsTheStartRequestTheDaemonExpects() {
        let preset = Preset(
            name: "Default",
            configPath: "/tmp/a.kbd",
            autorun: true,
            autorestartOnCrash: true,
            extraArgs: ["--quiet"]
        )
        let request = preset.startRequest
        XCTAssertEqual(request.presetName, "Default")
        XCTAssertEqual(request.configPath, "/tmp/a.kbd")
        XCTAssertTrue(request.autorestartOnCrash)
        XCTAssertEqual(request.extraArgs, ["--quiet"])
    }

    func testSigningRequirementNamesTheTeamAndIdentifier() {
        XCTAssertEqual(
            barnataCodeSigningRequirement(teamID: "EE3526PL64", identifier: barnataAppBundleIdentifier),
            "anchor apple generic and certificate leaf[subject.OU] = \"EE3526PL64\" and identifier \"io.jackyluong.barnata\""
        )
    }
}
