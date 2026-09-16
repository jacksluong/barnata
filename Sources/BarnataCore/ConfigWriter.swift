import Foundation

/// Line edits for the two keys the menu can toggle. The file is never re-serialized, so
/// comments, key order, and spacing survive a write.
public enum ConfigWriter {
    public enum Key: String, Sendable, CaseIterable {
        case launchAtLogin = "launch_at_login"
        case showDockIcon = "show_dock_icon"
    }

    public static let tableName = "app"

    public static func setting(_ key: Key, to value: Bool, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        guard let table = appTableRange(in: lines) else {
            let header = ["[\(tableName)]", "\(key.rawValue) = \(value)", ""]
            return (header + lines).joined(separator: "\n")
        }

        if let existing = table.first(where: { keyName(of: lines[$0]) == key.rawValue }) {
            lines[existing] = replacingValue(in: lines[existing], with: "\(value)")
            return lines.joined(separator: "\n")
        }

        let lastEntry = table.last { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        lines.insert("\(key.rawValue) = \(value)", at: lastEntry.map { $0 + 1 } ?? table.lowerBound)
        return lines.joined(separator: "\n")
    }

    // MARK: - Line parsing

    /// Lines between the `[app]` header and the next table header
    static func appTableRange(in lines: [String]) -> Range<Int>? {
        guard let header = lines.indices.first(where: { tableName(of: lines[$0]) == tableName }) else { return nil }
        let end = lines.indices.first { $0 > header && tableName(of: lines[$0]) != nil } ?? lines.count
        return (header + 1)..<end
    }

    /// Table name for a `[name]` header line, nil for anything else including `[[array]]`
    static func tableName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[["), let close = trimmed.lastIndex(of: "]") else { return nil }
        let inner = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        return inner.trimmingCharacters(in: .whitespaces)
    }

    static func keyName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["),
              let equals = trimmed.firstIndex(of: "=")
        else { return nil }

        var key = trimmed[trimmed.startIndex..<equals].trimmingCharacters(in: .whitespaces)
        if key.count >= 2, key.hasPrefix("\""), key.hasSuffix("\"") {
            key = String(key.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : key
    }

    /// Keeps the indentation, the key, the gap before a trailing comment, and the comment itself
    static func replacingValue(in line: String, with value: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return line }
        let head = line[line.startIndex...equals]
        let tail = line[line.index(after: equals)...]

        let commentStart = commentIndex(in: tail) ?? tail.endIndex
        let gap = tail[tail.startIndex..<commentStart].reversed().prefix { $0 == " " || $0 == "\t" }
        return head + " " + value + String(gap.reversed()) + tail[commentStart...]
    }

    /// Offset of the first `#` that is not inside a quoted string
    private static func commentIndex(in tail: Substring) -> Substring.Index? {
        var quote: Character?
        var index = tail.startIndex
        while index < tail.endIndex {
            let character = tail[index]
            if let open = quote {
                if character == "\\", open == "\"" { index = tail.index(after: index) } else if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return index
            }
            index = tail.index(after: index)
        }
        return nil
    }
}

/// Atomic writes of the toggled keys, reporting the modification date the watcher should ignore
public struct ConfigFileWriter: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    @discardableResult
    public func set(_ key: ConfigWriter.Key, to value: Bool) throws -> Date? {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = ConfigWriter.setting(key, to: value, in: existing)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appending(path: ".\(url.lastPathComponent).barnata-\(UUID().uuidString)")
        try updated.write(to: temporary, atomically: false, encoding: .utf8)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}
