import Foundation

public struct ArgAllowlistError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

/// The only kanata flags the daemon will pass through from a request
public enum ArgAllowlist {
    public static let booleanFlags: Set<String> = [
        "-n", "--nodelay",
        "-d", "--debug",
        "-t", "--trace",
        "-q", "--quiet",
        "--log-layer-changes",
        "--release-grab-on-lock",
    ]

    public static let intValueFlags: Set<String> = ["--emergency-exit-code"]

    public static func validate(_ args: [String]) throws {
        var index = args.startIndex
        while index < args.endIndex {
            let token = args[index]
            let (flag, inlineValue) = splitInlineValue(token)

            if booleanFlags.contains(flag) {
                guard inlineValue == nil else {
                    throw ArgAllowlistError(description: "\(flag) takes no value")
                }
                index += 1
                continue
            }

            if intValueFlags.contains(flag) {
                let value: String?
                if let inlineValue {
                    value = inlineValue
                    index += 1
                } else {
                    value = args.indices.contains(index + 1) ? args[index + 1] : nil
                    index += 2
                }
                guard let value, Int(value) != nil else {
                    throw ArgAllowlistError(description: "\(flag) requires an integer value")
                }
                continue
            }

            throw ArgAllowlistError(description: "\(token) is not an allowed kanata flag")
        }
    }

    private static func splitInlineValue(_ token: String) -> (String, String?) {
        guard token.hasPrefix("--"), let equals = token.firstIndex(of: "=") else { return (token, nil) }
        return (String(token[token.startIndex..<equals]), String(token[token.index(after: equals)...]))
    }
}
