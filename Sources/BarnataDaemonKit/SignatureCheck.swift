import BarnataCore
import Foundation

/// Validates a binary against a code signing requirement before the daemon runs it
public protocol BinaryValidating: Sendable {
    func validate(path: String, requirement: String) throws
}

public struct SignatureCheck: BinaryValidating {
    public static let pqrsTeamID = "G43BCU2T37"

    public init() {}

    public func validate(path: String, requirement: String) throws {
        try SignatureCheck.validate(path: path, requirement: requirement)
    }

    public static func validate(path: String, requirement: String) throws {
        try CodeSignature.validate(path: path, requirement: requirement)
    }

    /// pkgutil --check-signature, requiring a Developer ID Installer certificate for `teamID`
    public static func validatePackage(path: String, teamID: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SignatureError(path: path, reason: "file does not exist")
        }

        let result = Command.run("/usr/sbin/pkgutil", ["--check-signature", path])
        guard result.exitCode == 0 else {
            throw SignatureError(path: path, reason: "pkgutil --check-signature failed: \(result.combinedOutput)")
        }
        guard result.combinedOutput.contains("(\(teamID))") else {
            throw SignatureError(path: path, reason: "not signed by team \(teamID)")
        }
    }

    /// Team identifier from the daemon's own signature, so the client requirement needs no build-time constant
    public static func selfTeamIdentifier() -> String? {
        CodeSignature.selfTeamIdentifier()
    }
}
