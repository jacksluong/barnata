import Foundation
import XCTest

@testable import BarnataAppKit

final class UpdateInstallerTests: XCTestCase {
    private var script: String {
        UpdateInstaller.script(
            brew: "/opt/homebrew/bin/brew",
            appBundle: URL(fileURLWithPath: "/Applications/Barnata.app")
        )
    }

    /// Homebrew refuses to quit an app that `brew` is running inside, so the whole run is
    /// backgrounded and `sh` exits at once, leaving it parented to launchd
    func testTheRunIsBackgroundedSoNoAppIsLeftAboveHomebrew() {
        XCTAssertTrue(script.hasPrefix("{\n"), script)
        XCTAssertTrue(script.hasSuffix("\n} &"), script)
    }

    func testTheStepsRunInOrder() {
        let steps = [
            "/bin/kill -0 \(getpid())",
            "\"/opt/homebrew/bin/brew\" upgrade --cask jacksluong/tap/barnata",
            "echo \"$status\" > \"\(UpdateInstaller.statusURL.path)\"",
            "/usr/bin/open -a \"/Applications/Barnata.app\"",
        ]
        var searched = script[...]
        for step in steps {
            guard let range = searched.range(of: step) else { return XCTFail("\(step) is missing") }
            searched = searched[range.upperBound...]
        }
    }

    func testTheWaitForBarnataToQuitIsBounded() {
        XCTAssertTrue(script.contains("[ \"$waited\" -lt \(UpdateInstaller.quitWait) ]"), script)
    }

    /// Opening by path rather than by bundle id, because Homebrew only re-registers the new
    /// bundle with Launch Services when it is the one reopening the app
    func testTheAppIsOpenedByPath() {
        XCTAssertFalse(script.contains("open -b"))
    }
}
