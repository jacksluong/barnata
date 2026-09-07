import XCTest

@testable import BarnataDaemonKit

final class LogWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func contents(_ name: String) -> String? {
        try? String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    func testWritesAppendToOneFile() {
        let writer = LogWriter(url: directory.appending(path: "kanata.log"))
        writer.writeLine("first")
        writer.writeLine("second")

        XCTAssertEqual(contents("kanata.log"), "first\nsecond\n")
    }

    func testTheLogRotatesAtTheSizeCap() {
        let writer = LogWriter(url: directory.appending(path: "kanata.log"), maxBytes: 16, keptRotations: 3)
        writer.writeLine("aaaaaaaaaaaaaaaaaaaa")
        writer.writeLine("bbbb")

        XCTAssertEqual(contents("kanata.log.1"), "aaaaaaaaaaaaaaaaaaaa\n")
        XCTAssertEqual(contents("kanata.log"), "bbbb\n")
    }

    func testOnlyTheKeptRotationsSurvive() {
        let writer = LogWriter(url: directory.appending(path: "kanata.log"), maxBytes: 4, keptRotations: 3)
        for line in ["one", "two", "three", "four", "five"] {
            writer.writeLine(line)
        }

        let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(entries?.sorted(), ["kanata.log", "kanata.log.1", "kanata.log.2", "kanata.log.3"])
        XCTAssertEqual(contents("kanata.log"), "five\n")
        XCTAssertEqual(contents("kanata.log.1"), "four\n")
        XCTAssertEqual(contents("kanata.log.3"), "two\n")
    }

    func testTheDirectoryIsCreatedWithTheExpectedPermissions() throws {
        let nested = directory.appending(path: "Logs/Barnata")
        LogWriter(url: nested.appending(path: "kanata.log")).writeLine("hello")

        let attributes = try FileManager.default.attributesOfItem(atPath: nested.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o755)

        let file = try FileManager.default.attributesOfItem(atPath: nested.appending(path: "kanata.log").path)
        XCTAssertEqual(file[.posixPermissions] as? NSNumber, 0o644)
    }
}
