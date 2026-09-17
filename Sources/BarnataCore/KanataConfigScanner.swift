import Foundation

/// Reads layer names out of a kanata `.kbd` file, following `include` forms.
/// Only the shape of `deflayer`, `deflayermap`, and `include` matters, so the file is
/// tokenized rather than parsed.
public enum KanataConfigScanner {
    public static let maximumIncludeDepth = 8

    /// Layer names in file order, includes expanded, duplicates removed
    public static func layers(in url: URL, fileManager: FileManager = .default) -> [String] {
        var visited: Set<String> = []
        return layers(in: url, visited: &visited, depth: 0, fileManager: fileManager)
    }

    public static func layers(in text: String) -> [String] {
        ordered(layerNames(in: tokens(of: text)))
    }

    private static func layers(
        in url: URL,
        visited: inout Set<String>,
        depth: Int,
        fileManager: FileManager
    ) -> [String] {
        let path = url.standardizedFileURL.path
        guard depth <= maximumIncludeDepth, visited.insert(path).inserted else { return [] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let tokens = tokens(of: text)
        var names = layerNames(in: tokens)
        for include in includePaths(in: tokens) {
            let resolved = ConfigPath.expand(
                include,
                home: fileManager.homeDirectoryForCurrentUser,
                relativeTo: url.deletingLastPathComponent()
            )
            names += layers(in: URL(fileURLWithPath: resolved), visited: &visited, depth: depth + 1, fileManager: fileManager)
        }
        return ordered(names)
    }

    private static func ordered(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }

    // MARK: - Forms

    private static func layerNames(in tokens: [Token]) -> [String] {
        var names: [String] = []
        for (index, token) in tokens.enumerated() {
            guard case .atom(let head) = token, index > 0, tokens[index - 1] == .open else { continue }
            switch head {
            // (deflayer name ...)
            case "deflayer":
                if case .atom(let name)? = tokens[safe: index + 1] { names.append(name) }
            // (deflayermap (name) ...)
            case "deflayermap":
                guard tokens[safe: index + 1] == .open, case .atom(let name)? = tokens[safe: index + 2] else { continue }
                names.append(name)
            default:
                continue
            }
        }
        return names
    }

    private static func includePaths(in tokens: [Token]) -> [String] {
        var paths: [String] = []
        for (index, token) in tokens.enumerated() {
            guard token == .atom("include"), index > 0, tokens[index - 1] == .open else { continue }
            switch tokens[safe: index + 1] {
            case .string(let path)?, .atom(let path)?: paths.append(path)
            default: continue
            }
        }
        return paths
    }

    // MARK: - Tokenizer

    private enum Token: Equatable {
        case open
        case close
        case atom(String)
        case string(String)
    }

    /// Drops `;;` line comments and `#|…|#` block comments, keeps quoted strings whole
    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var atom = ""
        let characters = Array(text)
        var index = 0

        func endAtom() {
            if !atom.isEmpty {
                tokens.append(.atom(atom))
                atom = ""
            }
        }

        while index < characters.count {
            let character = characters[index]

            if character == ";", characters[safe: index + 1] == ";" {
                endAtom()
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if character == "#", characters[safe: index + 1] == "|" {
                endAtom()
                index += 2
                var depth = 1
                while index < characters.count, depth > 0 {
                    if characters[index] == "#", characters[safe: index + 1] == "|" {
                        depth += 1
                        index += 2
                    } else if characters[index] == "|", characters[safe: index + 1] == "#" {
                        depth -= 1
                        index += 2
                    } else {
                        index += 1
                    }
                }
                continue
            }
            if character == "\"" {
                endAtom()
                index += 1
                var value = ""
                while index < characters.count, characters[index] != "\"" {
                    if characters[index] == "\\", index + 1 < characters.count { index += 1 }
                    value.append(characters[index])
                    index += 1
                }
                index += 1
                tokens.append(.string(value))
                continue
            }
            if character == "(" || character == ")" {
                endAtom()
                tokens.append(character == "(" ? .open : .close)
                index += 1
                continue
            }
            if character.isWhitespace {
                endAtom()
                index += 1
                continue
            }
            atom.append(character)
            index += 1
        }
        endAtom()
        return tokens
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
