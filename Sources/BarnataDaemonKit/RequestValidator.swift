import BarnataCore
import Foundation

public struct ValidationError: Error, CustomStringConvertible, Equatable {
    public let rule: String
    public let detail: String

    public init(rule: String, detail: String) {
        self.rule = rule
        self.detail = detail
    }

    public var description: String { "\(rule): \(detail)" }
}

/// What the validator needs to know about a config file, so tests do not touch the disk
public struct FileFacts: Sendable, Equatable {
    public var isRegularFile: Bool
    public var ownerUID: uid_t
    public var isWorldReadable: Bool

    public init(isRegularFile: Bool, ownerUID: uid_t, isWorldReadable: Bool) {
        self.isRegularFile = isRegularFile
        self.ownerUID = ownerUID
        self.isWorldReadable = isWorldReadable
    }
}

public protocol FileInspecting: Sendable {
    /// nil when nothing exists at `path`
    func facts(forPath path: String) -> FileFacts?
}

/// stat(2), which follows symlinks, so a symlink to a directory reports a non-regular file
public struct PosixFileInspector: FileInspecting {
    public init() {}

    public func facts(forPath path: String) -> FileFacts? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileFacts(
            isRegularFile: (info.st_mode & S_IFMT) == S_IFREG,
            ownerUID: info.st_uid,
            isWorldReadable: (info.st_mode & S_IROTH) != 0
        )
    }
}

/// A request the daemon has accepted, with the exact argv it will pass to kanata
public struct ValidatedStartRequest: Sendable, Equatable {
    public var presetName: String
    /// nil for a child that takes no config file, such as the virtual HID daemon
    public var configPath: String?
    public var extraArgs: [String]
    public var autorestartOnCrash: Bool
    public var ownerUID: uid_t
    /// argv without the listen flag, which the supervisor adds once it has picked a port
    public var arguments: [String]

    public func arguments(listeningOn port: Int) -> [String] {
        arguments + ["-p", "\(RequestValidator.listenAddress):\(port)"]
    }
}

public struct RequestValidator: Sendable {
    public static let listenAddress = "127.0.0.1"

    private let inspector: FileInspecting

    public init(inspector: FileInspecting = PosixFileInspector()) {
        self.inspector = inspector
    }

    public func validate(_ request: StartRequest, ownerUID: uid_t) throws -> ValidatedStartRequest {
        let path = request.configPath
        guard !path.isEmpty else {
            throw ValidationError(rule: "config path", detail: "a start request needs a config file")
        }
        guard path.hasPrefix("/") else {
            throw ValidationError(rule: "config path must be absolute", detail: "\(path) is relative")
        }
        guard let facts = inspector.facts(forPath: path) else {
            throw ValidationError(rule: "config path must exist", detail: "\(path) does not exist")
        }
        guard facts.isRegularFile else {
            throw ValidationError(rule: "config path must be a regular file", detail: "\(path) is not a regular file")
        }
        guard facts.ownerUID == ownerUID || facts.isWorldReadable else {
            throw ValidationError(
                rule: "config file must be owned by the caller or world-readable",
                detail: "\(path) is owned by uid \(facts.ownerUID), not uid \(ownerUID), and is not world-readable"
            )
        }

        do {
            try ArgAllowlist.validate(request.extraArgs)
        } catch let error as ArgAllowlistError {
            throw ValidationError(rule: "extra argument not allowed", detail: error.description)
        }

        return ValidatedStartRequest(
            presetName: request.presetName,
            configPath: path,
            extraArgs: request.extraArgs,
            autorestartOnCrash: request.autorestartOnCrash,
            ownerUID: ownerUID,
            arguments: RequestValidator.arguments(for: request)
        )
    }

    static func arguments(for request: StartRequest) -> [String] {
        ["-c", request.configPath, "--no-wait"] + request.extraArgs
    }
}
