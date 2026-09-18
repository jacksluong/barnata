import BarnataCore
import XCTest

@testable import BarnataDaemonKit

final class RequestValidatorTests: XCTestCase {
    private let goodPath = "/Users/test/.config/kanata/example.kbd"

    private func validator(_ files: [String: FileFacts]) -> RequestValidator {
        RequestValidator(inspector: FakeFileInspector(files: files))
    }

    private func request(configPath: String? = nil, extraArgs: [String] = []) -> StartRequest {
        StartRequest(
            presetName: "Default",
            configPath: configPath ?? goodPath,
            extraArgs: extraArgs
        )
    }

    private func assertRejected(
        _ request: StartRequest,
        files: [String: FileFacts],
        rule: String,
        detailContains: String,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try validator(files).validate(request, ownerUID: callerUID), file: #filePath, line: line) { error in
            guard let error = error as? ValidationError else {
                return XCTFail("expected a ValidationError, got \(error)", file: #filePath, line: line)
            }
            XCTAssertEqual(error.rule, rule, file: #filePath, line: line)
            XCTAssertTrue(error.detail.contains(detailContains), error.detail, file: #filePath, line: line)
        }
    }

    func testAValidRequestIsAccepted() throws {
        let validated = try validator([goodPath: .regularFile()]).validate(request(), ownerUID: callerUID)
        XCTAssertEqual(validated.ownerUID, callerUID)
        XCTAssertEqual(validated.arguments, ["-c", goodPath, "--no-wait"])
    }

    func testExtraArgumentsFollowTheDaemonsOwnArguments() throws {
        let validated = try validator([goodPath: .regularFile()])
            .validate(request(extraArgs: ["--debug"]), ownerUID: callerUID)
        XCTAssertEqual(validated.arguments, ["-c", goodPath, "--no-wait", "--debug"])
    }

    func testRelativePathIsRejected() {
        assertRejected(
            request(configPath: "example.kbd"),
            files: ["example.kbd": .regularFile()],
            rule: "config path must be absolute",
            detailContains: "example.kbd is relative"
        )
    }

    func testNonexistentFileIsRejected() {
        assertRejected(
            request(),
            files: [:],
            rule: "config path must exist",
            detailContains: "does not exist"
        )
    }

    func testDirectoryIsRejected() {
        assertRejected(
            request(configPath: "/Users/test/.config/kanata"),
            files: ["/Users/test/.config/kanata": .directory()],
            rule: "config path must be a regular file",
            detailContains: "is not a regular file"
        )
    }

    /// stat follows symlinks, so a link to a directory looks like a directory here
    func testSymlinkToADirectoryIsRejected() {
        assertRejected(
            request(configPath: "/Users/test/link-to-configs"),
            files: ["/Users/test/link-to-configs": .directory()],
            rule: "config path must be a regular file",
            detailContains: "is not a regular file"
        )
    }

    func testFileOwnedByAnotherUserWithoutWorldReadIsRejected() {
        assertRejected(
            request(),
            files: [goodPath: .regularFile(ownedBy: otherUID, worldReadable: false)],
            rule: "config file must be owned by the caller or world-readable",
            detailContains: "owned by uid 502"
        )
    }

    func testFileOwnedByAnotherUserIsAcceptedWhenWorldReadable() throws {
        let files = [goodPath: FileFacts.regularFile(ownedBy: otherUID, worldReadable: true)]
        XCTAssertNoThrow(try validator(files).validate(request(), ownerUID: callerUID))
    }

    func testDisallowedFlagIsRejected() {
        assertRejected(
            request(extraArgs: ["--cfg", "/etc/passwd"]),
            files: [goodPath: .regularFile()],
            rule: "extra argument not allowed",
            detailContains: "--cfg is not an allowed kanata flag"
        )
    }

    func testAnEmptyConfigPathIsRejected() {
        assertRejected(
            request(configPath: ""),
            files: [:],
            rule: "config path",
            detailContains: "needs a config file"
        )
    }
}
