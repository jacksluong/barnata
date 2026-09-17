import Foundation

/// A TOML file as its own lines. Every edit is a line edit, so comments, key order,
/// and spacing outside the edited key survive a write.
public struct TOMLDocument: Equatable {
    public enum Value: Equatable {
        case bool(Bool)
        case integer(Int)
        case string(String)

        var literal: String {
            switch self {
            case .bool(let value): "\(value)"
            case .integer(let value): "\(value)"
            case .string(let value): TOMLEncode.string(value)
            }
        }
    }

    private var lines: [String]

    public init(_ text: String) {
        lines = text.components(separatedBy: "\n")
    }

    public var text: String { lines.joined(separator: "\n") }

    // MARK: - Reading

    public func hasTable(_ path: [String]) -> Bool { table(at: path) != nil }

    public func hasKey(_ key: String, inTable path: [String]) -> Bool {
        keyLine(key, inTable: path) != nil
    }

    /// Immediate child table names of `path`, in file order
    public func childTableNames(of path: [String]) -> [String] {
        tables.compactMap { table in
            guard table.path.count == path.count + 1, table.path.starts(with: path) else { return nil }
            return table.path.last
        }
    }

    // MARK: - Keys

    public mutating func set(_ value: Value, forKey key: String, inTable path: [String]) {
        guard let table = table(at: path) else {
            createTable(path, body: ["\(TOMLEncode.key(key)) = \(value.literal)"])
            return
        }
        if let existing = keyLine(key, inTable: path) {
            lines[existing] = TOMLLine.replacingValue(in: lines[existing], with: value.literal)
            return
        }
        let lastEntry = table.body.last { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        lines.insert("\(TOMLEncode.key(key)) = \(value.literal)", at: lastEntry.map { $0 + 1 } ?? table.body.lowerBound)
    }

    public mutating func removeKey(_ key: String, inTable path: [String]) {
        guard let index = keyLine(key, inTable: path) else { return }
        lines.remove(at: index)
    }

    // MARK: - Tables

    /// Inserts the table after the deepest ancestor already in the file, or at the end.
    /// `render` decides how the path is written out, which is how a caller keeps a quoting style.
    public mutating func createTable(
        _ path: [String],
        body: [String],
        render: ([String]) -> String = TOMLEncode.path
    ) {
        guard table(at: path) == nil else { return }
        let header = "[\(render(path))]"

        guard let anchor = anchorEnd(for: path) else {
            if let last = lines.indices.last, !lines[last].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: [header] + body)
            return
        }
        lines.insert(contentsOf: [header] + body + [""], at: anchor)
    }

    /// Removes the table and every table nested under it
    public mutating func removeTable(at path: [String]) {
        let victims = tables.filter { $0.path.starts(with: path) }
        guard let start = victims.map(\.header).min(), let end = victims.map(\.body.upperBound).max() else { return }
        lines.removeSubrange(start..<end)
        collapseBlankLines(around: start)
    }

    /// Rewrites the header of the table and of every table nested under it
    public mutating func renameTable(
        at path: [String],
        to newPath: [String],
        render: ([String]) -> String = TOMLEncode.path
    ) {
        guard path != newPath else { return }
        for table in tables where table.path.starts(with: path) {
            let renamed = newPath + table.path.dropFirst(path.count)
            lines[table.header] = TOMLLine.replacingHeader(in: lines[table.header], with: render(renamed))
        }
    }

    // MARK: - Line index

    private struct Table {
        var path: [String]
        var header: Int
        /// Lines after the header up to the next header
        var body: Range<Int>
    }

    private var tables: [Table] {
        var boundaries: [(line: Int, path: [String]?)] = []
        for (index, line) in lines.enumerated() {
            if let path = TOMLHeaderScanner.keyPath(in: line) {
                boundaries.append((index, path))
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("[[") {
                boundaries.append((index, nil))
            }
        }

        return boundaries.indices.compactMap { position in
            guard let path = boundaries[position].path else { return nil }
            let header = boundaries[position].line
            let end = position + 1 < boundaries.count ? boundaries[position + 1].line : lines.count
            return Table(path: path, header: header, body: (header + 1)..<end)
        }
    }

    private func table(at path: [String]) -> Table? {
        tables.first { $0.path == path }
    }

    private func keyLine(_ key: String, inTable path: [String]) -> Int? {
        guard let table = table(at: path) else { return nil }
        return table.body.first { TOMLLine.keyName(of: lines[$0]) == key }
    }

    /// Line after the last table whose path starts with the new table's parent
    private func anchorEnd(for path: [String]) -> Int? {
        guard path.count > 1 else { return nil }
        let parent = Array(path.dropLast())
        let family = tables.filter { $0.path.starts(with: parent) }
        guard let end = family.map(\.body.upperBound).max(), end < lines.count else { return nil }
        return end
    }

    private mutating func collapseBlankLines(around index: Int) {
        func isBlank(_ line: Int) -> Bool {
            lines.indices.contains(line) && lines[line].trimmingCharacters(in: .whitespaces).isEmpty
        }
        while isBlank(index), isBlank(index - 1) { lines.remove(at: index) }
        while let last = lines.indices.last, isBlank(last) { lines.removeLast() }
    }
}

/// Values and keys rendered back into TOML text
public enum TOMLEncode {
    public static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Bare when every character is allowed in a bare key, quoted otherwise
    public static func key(_ value: String) -> String {
        let bare = !value.isEmpty && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
        return bare ? value : string(value)
    }

    public static func path(_ segments: [String]) -> String {
        segments.map(key).joined(separator: ".")
    }
}

/// Reading and rewriting one line without disturbing the rest of it
enum TOMLLine {
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

    /// Keeps the indentation and any trailing comment, swapping only the bracketed path
    static func replacingHeader(in line: String, with path: String) -> String {
        guard let open = line.firstIndex(of: "[") else { return line }
        let rest = line[line.index(after: open)...]
        let end = commentIndex(in: rest) ?? rest.endIndex
        guard let close = rest[rest.startIndex..<end].lastIndex(of: "]") else { return line }
        return line[line.startIndex...open] + path + rest[close...]
    }

    /// Offset of the first `#` that is not inside a quoted string
    static func commentIndex(in tail: Substring) -> Substring.Index? {
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
