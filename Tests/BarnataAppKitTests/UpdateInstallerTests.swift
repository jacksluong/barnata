import Foundation
import XCTest

@testable import BarnataAppKit

final class UpdateInstallerTests: XCTestCase {
    private let staging = URL(fileURLWithPath: "/private/var/folders/xy/T/TemporaryItems/NSIRD_Barnata_1")

    private var script: String {
        UpdateInstaller.script(
            pid: 4242,
            staged: staging.appending(path: "Barnata.app"),
            appBundle: URL(fileURLWithPath: "/Applications/Barnata.app"),
            staging: staging
        )
    }

    private var app: String { "'/Applications/Barnata.app'" }
    private var new: String { "'\(staging.path)/Barnata.app'" }
    private var old: String { "'\(staging.path)/Barnata-old.app'" }

    /// The swap has to outlive Barnata, so the whole run is backgrounded and `sh` exits at once
    func testTheRunIsBackgrounded() {
        XCTAssertTrue(script.hasPrefix("{\n"), script)
        XCTAssertTrue(script.hasSuffix("\n} &"), script)
    }

    func testTheStepsRunInOrder() {
        let steps = [
            "/bin/kill -0 4242",
            "/bin/mv \(app) \(old)",
            "/bin/mv \(new) \(app)",
            "echo \"$status\" > '\(UpdateInstaller.statusURL.path)'",
            "/usr/bin/open \(app)",
            "/bin/rm -rf '\(staging.path)'",
        ]
        var searched = script[...]
        for step in steps {
            guard let range = searched.range(of: step) else { return XCTFail("\(step) is missing from\n\(script)") }
            searched = searched[range.upperBound...]
        }
    }

    func testTheOldAppIsPutBackWhenTheNewOneCannotMoveIn() {
        guard let failure = script.range(of: "! /bin/mv \(new) \(app); then") else {
            return XCTFail(script)
        }
        let rest = script[failure.upperBound...]
        XCTAssertNotNil(rest.range(of: "/bin/mv \(old) \(app)"), script)
        XCTAssertLessThan(
            rest.range(of: "/bin/mv \(old) \(app)")!.lowerBound,
            rest.range(of: "echo \"$status\"")!.lowerBound
        )
    }

    func testTheWaitForBarnataToQuitIsBounded() {
        XCTAssertTrue(script.contains("[ \"$waited\" -lt \(UpdateInstaller.quitWait) ]"), script)
    }

    func testTheAppIsOpenedByPath() {
        XCTAssertFalse(script.contains("open -b"))
        XCTAssertTrue(script.contains("/usr/bin/open \(app)\n"), script)
    }

    func testPathsAreQuotedForTheShell() {
        XCTAssertEqual(UpdateInstaller.quoted("/tmp/it's here"), "'/tmp/it'\\''s here'")
    }

    func testOnlyTheApplicationsCopyCanBeUpdated() {
        XCTAssertTrue(UpdateInstaller.isInstallable(bundle: URL(fileURLWithPath: "/Applications/Barnata.app")))
        XCTAssertTrue(UpdateInstaller.isInstallable(bundle: URL(fileURLWithPath: "/Applications/Barnata.app/")))
        XCTAssertFalse(UpdateInstaller.isInstallable(bundle: URL(
            fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/0A1B2C3D/d/Barnata.app")))
        XCTAssertFalse(UpdateInstaller.isInstallable(bundle: URL(fileURLWithPath: "/Users/someone/Downloads/Barnata.app")))
        XCTAssertFalse(UpdateInstaller.isInstallable(bundle: URL(fileURLWithPath: "/Applications/Barnata 2.app")))
    }

    func testTheHashOfAKnownFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "barnata-hash-\(UUID().uuidString)")
        try Data("barnata\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(
            try UpdateInstaller.sha256Hex(of: file),
            "577aeff370350676e164e4c6ce5e9498ee9282ac3b5eb782925103a99762071f"
        )
    }
}
