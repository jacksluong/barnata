import BarnataCore
import XCTest

@testable import BarnataDaemonKit

/// Exercises the real posix_spawn path against system tools, without needing root
final class PosixSpawnerTests: XCTestCase {
    private let spawner = PosixSpawner()

    private func run(_ path: String, _ arguments: [String]) throws -> (reason: ExitReason, stdout: String, stderr: String) {
        let child = try spawner.spawn(
            SpawnRequest(executablePath: path, arguments: arguments, environment: SpawnRequest.daemonChildEnvironment)
        )

        let finished = expectation(description: "\(path) exits")
        let box = ExitBox()
        spawner.wait(for: child.pid) { reason in
            box.reason = reason
            finished.fulfill()
        }

        let stdout = readAll(child.standardOutput)
        let stderr = readAll(child.standardError)
        wait(for: [finished], timeout: 10)

        return (try XCTUnwrap(box.reason), stdout, stderr)
    }

    private func readAll(_ fileDescriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fileDescriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        close(fileDescriptor)
        return String(decoding: data, as: UTF8.self)
    }

    func testStandardOutputIsCaptured() throws {
        let result = try run("/bin/echo", ["hello"])
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.reason, .exited(code: 0))
        XCTAssertFalse(result.reason.isCrash)
    }

    func testANonZeroExitIsReportedAsACrash() throws {
        let result = try run("/usr/bin/false", [])
        XCTAssertEqual(result.reason, .exited(code: 1))
        XCTAssertTrue(result.reason.isCrash)
    }

    func testTheChildOnlySeesTheFixedEnvironment() throws {
        let result = try run("/usr/bin/env", [])
        let variables = Set(result.stdout.split(separator: "\n").map(String.init))
        XCTAssertEqual(variables, ["PATH=/usr/bin:/bin", "HOME=/var/root"])
    }

    func testStandardErrorIsCapturedSeparately() throws {
        let result = try run("/bin/sh", ["-c", "echo out; echo err >&2"])
        XCTAssertEqual(result.stdout, "out\n")
        XCTAssertEqual(result.stderr, "err\n")
    }

    func testSpawningAMissingExecutableThrows() {
        XCTAssertThrowsError(
            try spawner.spawn(
                SpawnRequest(
                    executablePath: "/does/not/exist",
                    arguments: [],
                    environment: SpawnRequest.daemonChildEnvironment
                )
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("/does/not/exist"), "\(error)")
        }
    }

    func testSIGTERMTerminatesTheChild() throws {
        let child = try spawner.spawn(
            SpawnRequest(
                executablePath: "/bin/sleep",
                arguments: ["30"],
                environment: SpawnRequest.daemonChildEnvironment
            )
        )

        let finished = expectation(description: "sleep is terminated")
        let box = ExitBox()
        spawner.wait(for: child.pid) { reason in
            box.reason = reason
            finished.fulfill()
        }
        spawner.signal(SIGTERM, to: child.pid)
        wait(for: [finished], timeout: 10)

        XCTAssertEqual(box.reason, .signaled(signal: SIGTERM))
        close(child.standardOutput)
        close(child.standardError)
    }

    /// The bundled kanata is only present after build-app.sh, so this check is skipped otherwise
    func testTheSupervisorRunsTheRealKanata() throws {
        let kanata = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "build/kanata")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: kanata.path), "run Scripts/fetch-kanata.sh first")

        let result = try run(kanata.path, ["--version"])
        XCTAssertEqual(result.reason, .exited(code: 0))
        XCTAssertTrue(result.stdout.hasPrefix("kanata "), result.stdout)
    }
}

private final class ExitBox: @unchecked Sendable {
    var reason: ExitReason?
}
