import Foundation
import XCTest

@testable import BarnataAppKit

final class UpdateCheckerTests: XCTestCase {
    private func release(
        tag: String,
        body: String? = "Fixed the thing",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [String]? = nil
    ) -> Data {
        var fields: [String] = [
            "\"tag_name\": \"\(tag)\"",
            "\"html_url\": \"https://github.com/jacksluong/barnata/releases/tag/\(tag)\"",
            "\"draft\": \(draft)",
            "\"prerelease\": \(prerelease)",
        ]
        if let body { fields.append("\"body\": \"\(body)\"") }
        if let assets { fields.append("\"assets\": [\(assets.joined(separator: ","))]") }
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

    private let digestHex = String(repeating: "ab", count: 32)

    private func asset(_ name: String, digest: String? = nil) -> String {
        var fields = [
            "\"name\": \"\(name)\"",
            "\"browser_download_url\": \"https://github.com/jacksluong/barnata/releases/download/v1.0.0/\(name)\"",
        ]
        if let digest { fields.append("\"digest\": \"\(digest)\"") }
        return "{\(fields.joined(separator: ","))}"
    }

    func testTheDMGAssetIsPickedByExactName() {
        let data = release(tag: "v1.0.0", assets: [
            asset("Barnata-1.0.0.dmg.sig", digest: "sha256:\(String(repeating: "00", count: 32))"),
            asset("Barnata-1.0.0.dmg", digest: "sha256:\(digestHex)"),
            asset("Barnata-0.9.0.dmg", digest: "sha256:\(String(repeating: "11", count: 32))"),
        ])
        let update = UpdateChecker.update(in: data, above: "0.2.1")
        XCTAssertEqual(update?.downloadURL?.lastPathComponent, "Barnata-1.0.0.dmg")
        XCTAssertEqual(update?.sha256, digestHex)
    }

    func testTheDigestPrefixIsStrippedAndTheHexLowercased() {
        let data = release(tag: "v1.0.0", assets: [asset("Barnata-1.0.0.dmg", digest: "sha256:\(digestHex.uppercased())")])
        XCTAssertEqual(UpdateChecker.update(in: data, above: "0.2.1")?.sha256, digestHex)
        XCTAssertNil(UpdateChecker.sha256Hex(fromDigest: "sha512:\(digestHex)"))
        XCTAssertNil(UpdateChecker.sha256Hex(fromDigest: "sha256:abc"))
    }

    func testAReleaseWithoutAssetsIsStillOfferedWithoutADownload() {
        let update = UpdateChecker.update(in: release(tag: "v1.0.0"), above: "0.2.1")
        XCTAssertEqual(update?.version, "1.0.0")
        XCTAssertNil(update?.downloadURL)
        XCTAssertNil(update?.sha256)
    }

    func testAZipOnlyReleaseHasNoDownload() {
        let data = release(tag: "v1.0.0", assets: [asset("Barnata-1.0.0.zip", digest: "sha256:\(digestHex)")])
        let update = UpdateChecker.update(in: data, above: "0.2.1")
        XCTAssertEqual(update?.version, "1.0.0")
        XCTAssertNil(update?.downloadURL)
        XCTAssertNil(update?.sha256)
    }
}
