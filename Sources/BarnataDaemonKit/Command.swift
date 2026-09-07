import Foundation

/// Runs a fixed system tool and collects its output. Never a shell, never a path from a request.
enum Command {
    struct Result {
        var exitCode: Int32
        var combinedOutput: String
    }

    static func run(_ executablePath: String, _ arguments: [String]) -> Result {
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
