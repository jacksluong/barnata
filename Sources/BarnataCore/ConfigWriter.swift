import Foundation

/// Line edits for the keys the app can change. The file is never re-serialized, so
/// comments, key order, and spacing survive a write.
public enum ConfigWriter {
    public enum Key: String, Sendable, CaseIterable {
        case launchAtLogin = "launch_at_login"
        case showDockIcon = "show_dock_icon"
    }

    public static let tableName = "app"
    public static let presetsTableName = "presets"
    public static let layerIconsTableName = "layer_icons"
    public static let kanataConfigKey = "kanata_config"

    public static func setting(_ key: Key, to value: Bool, in text: String) -> String {
        var document = TOMLDocument(text)
        guard document.hasTable([tableName]) else {
            let header = ["[\(tableName)]", "\(key.rawValue) = \(value)", ""]
            return (header + text.components(separatedBy: "\n")).joined(separator: "\n")
        }
        document.set(.bool(value), forKey: key.rawValue, inTable: [tableName])
        return document.text
    }

    // MARK: - Presets

    public static func presetPath(_ name: String) -> [String] { [presetsTableName, name] }

    public static func layerIconsPath(_ preset: String) -> [String] {
        presetPath(preset) + [layerIconsTableName]
    }

    /// Preset names are written quoted, the way `docs/02-config-format.md` spells them
    public static func renderPath(_ segments: [String]) -> String {
        segments.enumerated()
            .map { $0.offset == 1 ? TOMLEncode.string($0.element) : TOMLEncode.key($0.element) }
            .joined(separator: ".")
    }

    /// A preset holding one config file, appended after the presets already in the file
    public static func addPreset(_ name: String, configPath: String, to document: inout TOMLDocument) {
        document.createTable(
            presetPath(name),
            body: ["\(kanataConfigKey) = \(TOMLEncode.string(configPath))"],
            render: renderPath
        )
    }

    public static func removePreset(_ name: String, from document: inout TOMLDocument) {
        document.removeTable(at: presetPath(name))
    }

    public static func renamePreset(_ name: String, to newName: String, in document: inout TOMLDocument) {
        document.renameTable(at: presetPath(name), to: presetPath(newName), render: renderPath)
    }

    /// Sets one layer's icon, or clears it when `symbol` is nil.
    /// A preset with no `layer_icons` of its own inherits the defaults table, so the inherited
    /// map is materialized first and the edit applied on top of it.
    public static func setLayerIcon(
        preset: String,
        layer: String,
        symbol: String?,
        inherited: [String: String],
        in document: inout TOMLDocument
    ) {
        let table = layerIconsPath(preset)

        if document.hasKey(layerIconsTableName, inTable: presetPath(preset)) {
            // An inline `layer_icons = { … }` cannot take a sub-table, so normalize it into one
            document.removeKey(layerIconsTableName, inTable: presetPath(preset))
        }
        if !document.hasTable(table) {
            document.createTable(
                table,
                body: inherited.sorted { $0.key < $1.key }.map {
                    "\(TOMLEncode.key($0.key)) = \(TOMLEncode.string($0.value))"
                },
                render: renderPath
            )
        }

        if let symbol {
            document.set(.string(symbol), forKey: layer, inTable: table)
        } else {
            document.removeKey(layer, inTable: table)
        }
    }
}

/// Atomic writes of the config file, reporting the modification date the watcher should ignore
public struct ConfigFileWriter: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    @discardableResult
    public func set(_ key: ConfigWriter.Key, to value: Bool) throws -> Date? {
        try write { ConfigWriter.setting(key, to: value, in: $0) }
    }

    @discardableResult
    public func edit(_ body: (inout TOMLDocument) -> Void) throws -> Date? {
        try write { text in
            var document = TOMLDocument(text)
            body(&document)
            return document.text
        }
    }

    private func write(_ transform: (String) -> String) throws -> Date? {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = transform(existing)

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
