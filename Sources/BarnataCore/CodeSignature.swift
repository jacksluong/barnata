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

/// The running process's own signing identity, so neither side needs a build-time Team ID constant
public enum CodeSignature {
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

    /// Static code check of the file or bundle at `path` against a code signing requirement
    public static func validate(
        path: String,
        requirement: String,
        flags: SecCSFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
    ) throws {
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

        let checkStatus = SecStaticCodeCheckValidity(staticCode, flags, secRequirement)
        guard checkStatus == errSecSuccess else {
            throw SignatureError(path: path, reason: "does not satisfy \(requirement): \(message(for: checkStatus))")
        }
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
    }
}
