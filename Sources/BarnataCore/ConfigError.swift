import Foundation

public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public let keyPath: String?
    public let reason: String

    public init(keyPath: String?, reason: String) {
        self.keyPath = keyPath
        self.reason = reason
    }

    public var description: String {
        guard let keyPath else { return reason }
        return "\(keyPath): \(reason)"
    }
}

extension String {
    /// Quotes a TOML key for use in an error message when it is not a bare key
    var tomlKeyPathSegment: String {
        let bare = allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return bare && !isEmpty ? self : "\"\(self)\""
    }
}
