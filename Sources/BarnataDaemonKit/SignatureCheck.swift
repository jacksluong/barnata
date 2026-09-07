import Foundation
import Security

public struct SignatureError: Error, CustomStringConvertible, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var description: String { "\(path): \(reason)" }
}

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
        guard FileManager.default.fileExists(atPath: path) else {
            throw SignatureError(path: path, reason: "file does not exist")
        }

        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw SignatureError(path: path, reason: "cannot read the code signature (\(message(for: createStatus))")
        }

        var secRequirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(requirement as CFString, [], &secRequirement)
        guard requirementStatus == errSecSuccess, let secRequirement else {
            throw SignatureError(path: path, reason: "malformed requirement \(requirement)")
        }

        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), secRequirement)
        guard checkStatus == errSecSuccess else {
            throw SignatureError(path: path, reason: "does not satisfy \(requirement): \(message(for: checkStatus))")
        }
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
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return nil }

        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
    }
}
