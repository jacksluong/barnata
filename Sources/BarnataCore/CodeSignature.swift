import Foundation
import Security

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
}
