import Foundation

/// Reads table headers straight from the file text, because the parser sorts keys and the menu follows file order
enum TOMLHeaderScanner {
    static func presetNamesInFileOrder(_ text: String) -> [String] {
        var names: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let path = keyPath(in: String(line)), path.count == 2, path[0] == "presets" else { continue }
            names.append(path[1])
        }
        return names
    }

    static func keyPath(in line: String) -> [String]? {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        guard characters.first == "[" else { return nil }
        guard characters.count > 1, characters[1] != "[" else { return nil }

        var index = 1
        var segments: [String] = []

        while index < characters.count {
            skipWhitespace(characters, &index)
            guard index < characters.count, characters[index] != "]" else { return nil }

            guard let segment = readSegment(characters, &index) else { return nil }
            segments.append(segment)

            skipWhitespace(characters, &index)
            guard index < characters.count else { return nil }
            switch characters[index] {
            case ".": index += 1
            case "]": return segments
            default: return nil
            }
        }
        return nil
    }

    private static func readSegment(_ characters: [Character], _ index: inout Int) -> String? {
        if characters[index] == "\"" || characters[index] == "'" {
            let quote = characters[index]
            var segment = ""
            index += 1
            while index < characters.count, characters[index] != quote {
                if quote == "\"", characters[index] == "\\", index + 1 < characters.count {
                    index += 1
                    segment.append(unescape(characters[index]))
                } else {
                    segment.append(characters[index])
                }
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
            return segment
        }

        var segment = ""
        while index < characters.count, isBareKeyCharacter(characters[index]) {
            segment.append(characters[index])
            index += 1
        }
        return segment.isEmpty ? nil : segment
    }

    private static func skipWhitespace(_ characters: [Character], _ index: inout Int) {
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
    }

    private static func isBareKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private static func unescape(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        default: character
        }
    }
}
