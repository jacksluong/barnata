import Foundation

public struct SpawnRequest: Sendable, Equatable {
    public var executablePath: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executablePath: String, arguments: [String], environment: [String: String]) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }

    /// Fixed environment for every child, per the privilege boundary
    public static let daemonChildEnvironment = ["PATH": "/usr/bin:/bin", "HOME": "/var/root"]
}

public struct SpawnedProcess: Sendable, Equatable {
    public var pid: pid_t
    /// Read ends of the child's pipes, -1 when the platform gave none
    public var standardOutput: Int32
    public var standardError: Int32
    public var responsibilityDisclaimed: Bool

    public init(pid: pid_t, standardOutput: Int32 = -1, standardError: Int32 = -1, responsibilityDisclaimed: Bool = false) {
        self.pid = pid
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.responsibilityDisclaimed = responsibilityDisclaimed
    }
}

public enum ExitReason: Sendable, Equatable {
    case exited(code: Int32)
    case signaled(signal: Int32)

    /// kanata's emergency exit leaves with code 0, so only a non-zero code or a signal is a crash
    public var isCrash: Bool {
        switch self {
        case .exited(let code): code != 0
        case .signaled: true
        }
    }

    public var code: Int32 {
        switch self {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }
}

public struct SpawnError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

public protocol Spawner: Sendable {
    func spawn(_ request: SpawnRequest) throws -> SpawnedProcess
    func signal(_ signal: Int32, to pid: pid_t)
    func wait(for pid: pid_t, completion: @escaping @Sendable (ExitReason) -> Void)
}
