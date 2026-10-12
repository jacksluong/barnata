import Foundation

/// Runs a fixed system tool and collects its output. Never a shell, never a path from a request.
public enum Command {
    public struct Result: Sendable {
        public var exitCode: Int32
        public var combinedOutput: String

        public init(exitCode: Int32, combinedOutput: String) {
            self.exitCode = exitCode
            self.combinedOutput = combinedOutput
        }
    }

    public static func run(_ executablePath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, combinedOutput: "cannot run \(executablePath): \(error.localizedDescription)")
        }

        let handle = pipe.fileHandleForReading
        let output = (try? handle.readToEnd()) ?? Data()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            combinedOutput: String(decoding: output, as: UTF8.self)
        )
    }
}
