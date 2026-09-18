import Foundation
import XCTest

@testable import BarnataAppKit

final class UpdateCheckerTests: XCTestCase {
    private func release(
        tag: String,
        body: String? = "Fixed the thing",
        draft: Bool = false,
        prerelease: Bool = false
    ) -> Data {
        var fields: [String] = [
            "\"tag_name\": \"\(tag)\"",
            "\"html_url\": \"https://github.com/jacksluong/barnata/releases/tag/\(tag)\"",
            "\"draft\": \(draft)",
            "\"prerelease\": \(prerelease)",
        ]
        if let body { fields.append("\"body\": \"\(body)\"") }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    func testANewerTagIsOfferedWithoutItsVPrefix() {
        let update = UpdateChecker.update(in: release(tag: "v0.3.0"), above: "0.2.1")
        XCTAssertEqual(update?.version, "0.3.0")
        XCTAssertEqual(update?.notes, "Fixed the thing")
        XCTAssertEqual(update?.pageURL?.lastPathComponent, "v0.3.0")
    }

    func testTheRunningVersionAndOlderOnesAreNotOffered() {
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v0.2.1"), above: "0.2.1"))
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v0.2.0"), above: "0.2.1"))
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v0.9.0"), above: "0.10.0"))
    }

    func testDraftsAndPrereleasesAreSkipped() {
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v9.0.0", draft: true), above: "0.2.1"))
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v9.0.0", prerelease: true), above: "0.2.1"))
    }

    func testAnEmptyOrMissingBodyLeavesTheNotesOut() {
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v1.0.0", body: nil), above: "0.2.1")?.notes)
        XCTAssertNil(UpdateChecker.update(in: release(tag: "v1.0.0", body: "  "), above: "0.2.1")?.notes)
    }

    func testAnythingThatIsNotAReleaseIsIgnored() {
        XCTAssertNil(UpdateChecker.update(in: Data("{\"message\":\"Not Found\"}".utf8), above: "0.2.1"))
        XCTAssertNil(UpdateChecker.update(in: Data("not json".utf8), above: "0.2.1"))
    }
}
