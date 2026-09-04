import XCTest

@testable import BarnataCore

final class ArgAllowlistTests: XCTestCase {
    func testAllowedBooleanFlagsPass() throws {
        let cases: [[String]] = [
            ["-n"], ["--nodelay"], ["-d"], ["--debug"], ["-t"], ["--trace"], ["-q"], ["--quiet"],
            ["--log-layer-changes"], ["--release-grab-on-lock"], ["--debug", "--nodelay"], [],
        ]
        for args in cases {
            XCTAssertNoThrow(try ArgAllowlist.validate(args), "\(args)")
        }
    }

    func testEmergencyExitCodeAcceptsAnInteger() throws {
        for args in [["--emergency-exit-code", "3"], ["--emergency-exit-code=3"], ["--emergency-exit-code", "-1"]] {
            XCTAssertNoThrow(try ArgAllowlist.validate(args), "\(args)")
        }
    }

    func testEmergencyExitCodeRejectsANonInteger() {
        for args in [["--emergency-exit-code", "x"], ["--emergency-exit-code=x"], ["--emergency-exit-code"]] {
            XCTAssertThrowsError(try ArgAllowlist.validate(args), "\(args)") { error in
                XCTAssertEqual("\(error as! ArgAllowlistError)", "--emergency-exit-code requires an integer value")
            }
        }
    }

    func testUnknownFlagIsRejectedByName() {
        for arg in ["--danger", "--cmd-enabled", "-c", "/tmp/a.kbd"] {
            XCTAssertThrowsError(try ArgAllowlist.validate([arg]), arg) { error in
                XCTAssertEqual("\(error as! ArgAllowlistError)", "\(arg) is not an allowed kanata flag")
            }
        }
    }

    func testBooleanFlagWithAValueIsRejected() {
        XCTAssertThrowsError(try ArgAllowlist.validate(["--debug=1"])) { error in
            XCTAssertEqual("\(error as! ArgAllowlistError)", "--debug takes no value")
        }
    }

    func testBadFlagAfterGoodOnesIsCaught() {
        XCTAssertThrowsError(try ArgAllowlist.validate(["--debug", "--emergency-exit-code", "3", "--danger"])) { error in
            XCTAssertTrue("\(error)".contains("--danger"), "\(error)")
        }
    }
}
