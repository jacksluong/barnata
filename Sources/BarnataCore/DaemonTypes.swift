import Foundation

public enum KanataState: String, Codable, Sendable {
    case idle
    case starting
    case running
    case crashed
    case stopping
}

public struct StartRequest: Codable, Sendable, Equatable {
    public var presetName: String
    public var configPaths: [String]
    public var tcpPort: Int
    public var extraArgs: [String]
    public var autorestartOnCrash: Bool

    public init(
        presetName: String,
        configPaths: [String],
        tcpPort: Int,
        extraArgs: [String] = [],
        autorestartOnCrash: Bool = false
    ) {
        self.presetName = presetName
        self.configPaths = configPaths
        self.tcpPort = tcpPort
        self.extraArgs = extraArgs
        self.autorestartOnCrash = autorestartOnCrash
    }
}

public struct DriverStatus: Codable, Sendable, Equatable {
    public var installed: Bool
    public var version: String?
    public var requiredVersion: String
    public var activated: Bool
    public var vhidDaemonRunning: Bool
    public var vhidDaemonManagedByBarnata: Bool

    public init(
        installed: Bool = false,
        version: String? = nil,
        requiredVersion: String,
        activated: Bool = false,
        vhidDaemonRunning: Bool = false,
        vhidDaemonManagedByBarnata: Bool = false
    ) {
        self.installed = installed
        self.version = version
        self.requiredVersion = requiredVersion
        self.activated = activated
        self.vhidDaemonRunning = vhidDaemonRunning
        self.vhidDaemonManagedByBarnata = vhidDaemonManagedByBarnata
    }
}

public struct DaemonStatus: Codable, Sendable, Equatable {
    public var daemonVersion: String
    public var kanataVersion: String?
    public var state: KanataState
    public var pid: Int32?
    public var presetName: String?
    public var configPaths: [String]
    public var tcpPort: Int?
    public var ownerUID: uid_t?
    public var lastExitCode: Int32?
    public var lastError: String?
    public var restartCount: Int
    public var driver: DriverStatus

    public init(
        daemonVersion: String,
        kanataVersion: String? = nil,
        state: KanataState = .idle,
        pid: Int32? = nil,
        presetName: String? = nil,
        configPaths: [String] = [],
        tcpPort: Int? = nil,
        ownerUID: uid_t? = nil,
        lastExitCode: Int32? = nil,
        lastError: String? = nil,
        restartCount: Int = 0,
        driver: DriverStatus
    ) {
        self.daemonVersion = daemonVersion
        self.kanataVersion = kanataVersion
        self.state = state
        self.pid = pid
        self.presetName = presetName
        self.configPaths = configPaths
        self.tcpPort = tcpPort
        self.ownerUID = ownerUID
        self.lastExitCode = lastExitCode
        self.lastError = lastError
        self.restartCount = restartCount
        self.driver = driver
    }
}

public struct CommandResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?
    public var output: String?

    public init(ok: Bool, message: String? = nil, output: String? = nil) {
        self.ok = ok
        self.message = message
        self.output = output
    }

    public static func failure(_ message: String, output: String? = nil) -> CommandResult {
        CommandResult(ok: false, message: message, output: output)
    }

    public static let success = CommandResult(ok: true)
}
