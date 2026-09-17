import Foundation
import TOMLKit

public enum ConfigLoader {
    public static let environmentKey = "BARNATA_CONFIG"

    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: ConfigPath.expand(override, home: home, relativeTo: home))
        }
        return home.appending(path: ".config/barnata/config.toml")
    }

    /// Written to a config path that has no file yet, so a fresh install has something to read and edit
    public static let template = """
    [app]
    show_dock_icon = false

    [defaults]
    autorestart_on_crash = false

    """

    /// Creates the config file and its directory when absent. Returns true when a file was written.
    @discardableResult
    public static func createIfMissing(at url: URL) -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try template.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    public static func load(
        from url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Config {
        createIfMissing(at: url)
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError(keyPath: nil, reason: "cannot read \(url.path): \(error.localizedDescription)")
        }
        return try parse(text, directory: url.deletingLastPathComponent(), home: home)
    }

    public static func parse(
        _ text: String,
        directory: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: text)
        } catch let error as TOMLParseError {
            throw ConfigError(keyPath: nil, reason: "invalid TOML at \(error.source.begin.debugDescription): \(error.description)")
        }

        let reader = TableReader(table: root, keyPath: nil)
        try reader.rejectUnknownKeys(["app", "defaults", "presets"])

        let app = try parseApp(try reader.table(named: "app"))
        let defaults = try parseDefaults(try reader.table(named: "defaults"))
        let presets = try parsePresets(
            try reader.table(named: "presets"),
            order: TOMLHeaderScanner.presetNamesInFileOrder(text),
            defaults: defaults,
            directory: directory,
            home: home
        )

        let autorunCount = presets.filter(\.autorun).count
        guard autorunCount <= 1 else {
            throw ConfigError(keyPath: "presets", reason: "at most one preset may set autorun, found \(autorunCount)")
        }

        return Config(app: app, defaults: defaults, presets: presets)
    }

    private static func parseApp(_ reader: TableReader?) throws -> AppSettings {
        guard let reader else { return AppSettings() }
        try reader.rejectUnknownKeys(["launch_at_login", "show_dock_icon", "status_icons"])
        return AppSettings(
            launchAtLogin: try reader.bool(named: "launch_at_login"),
            showDockIcon: try reader.bool(named: "show_dock_icon") ?? false,
            statusIcons: try reader.string(named: "status_icons")
        )
    }

    private static func parseDefaults(_ reader: TableReader?) throws -> PresetDefaults {
        guard let reader else { return PresetDefaults() }
        try reader.rejectUnknownKeys(["autorestart_on_crash", "extra_args", "layer_icons"])
        return PresetDefaults(
            autorestartOnCrash: try reader.bool(named: "autorestart_on_crash") ?? false,
            extraArgs: try reader.extraArgs(named: "extra_args") ?? [],
            layerIcons: try reader.stringTable(named: "layer_icons") ?? [:]
        )
    }

    private static func parsePresets(
        _ reader: TableReader?,
        order: [String],
        defaults: PresetDefaults,
        directory: URL,
        home: URL
    ) throws -> [Preset] {
        guard let reader else { return [] }
        let declared = Set(reader.table.keys)
        let names = order.filter(declared.contains) + declared.subtracting(order).sorted()

        return try names.map { name in
            guard let preset = try reader.table(named: name) else {
                throw ConfigError(keyPath: "presets.\(name.tomlKeyPathSegment)", reason: "expected a table")
            }
            try preset.rejectUnknownKeys([
                "kanata_config", "autorun", "autorestart_on_crash", "extra_args", "layer_icons",
            ])

            let rawPaths = try preset.stringOrStringArray(named: "kanata_config")
            guard let rawPaths, !rawPaths.isEmpty else {
                throw ConfigError(keyPath: "\(preset.prefix)kanata_config", reason: "required, a path or an array of paths")
            }

            return Preset(
                name: name,
                configPaths: rawPaths.map { ConfigPath.expand($0, home: home, relativeTo: directory) },
                autorun: try preset.bool(named: "autorun") ?? false,
                autorestartOnCrash: try preset.bool(named: "autorestart_on_crash") ?? defaults.autorestartOnCrash,
                extraArgs: try preset.extraArgs(named: "extra_args") ?? defaults.extraArgs,
                layerIcons: try preset.stringTable(named: "layer_icons") ?? defaults.layerIcons
            )
        }
    }
}

public enum ConfigPath {
    /// Expands a leading `~` and makes the result absolute against `base`
    public static func expand(_ path: String, home: URL, relativeTo base: URL) -> String {
        var expanded = path
        if expanded == "~" {
            expanded = home.path
        } else if expanded.hasPrefix("~/") {
            expanded = home.appending(path: String(expanded.dropFirst(2))).path
        }
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : base.appending(path: expanded)
        return url.standardizedFileURL.path
    }
}

private struct TableReader {
    let table: TOMLTable
    let keyPath: String?

    var prefix: String { keyPath.map { "\($0)." } ?? "" }

    func path(_ key: String) -> String { "\(prefix)\(key.tomlKeyPathSegment)" }

    func rejectUnknownKeys(_ allowed: Set<String>) throws {
        for key in table.keys.sorted() where !allowed.contains(key) {
            throw ConfigError(keyPath: path(key), reason: "unknown key")
        }
    }

    func table(named key: String) throws -> TableReader? {
        guard let value = table[key] else { return nil }
        guard let child = value.table else { throw ConfigError(keyPath: path(key), reason: "expected a table") }
        return TableReader(table: child, keyPath: path(key))
    }

    func bool(named key: String) throws -> Bool? {
        guard let value = table[key] else { return nil }
        guard let result = value.bool else { throw ConfigError(keyPath: path(key), reason: "expected true or false") }
        return result
    }

    func string(named key: String) throws -> String? {
        guard let value = table[key] else { return nil }
        guard let result = value.string else { throw ConfigError(keyPath: path(key), reason: "expected a string") }
        return result
    }

    func stringOrStringArray(named key: String) throws -> [String]? {
        guard let value = table[key] else { return nil }
        if let single = value.string { return [single] }
        guard let array = value.array else {
            throw ConfigError(keyPath: path(key), reason: "expected a string or an array of strings")
        }
        return try (0..<array.count).map { index in
            guard let element = array[index].string else {
                throw ConfigError(keyPath: "\(path(key))[\(index)]", reason: "expected a string")
            }
            return element
        }
    }

    func extraArgs(named key: String) throws -> [String]? {
        guard let args = try stringOrStringArray(named: key) else { return nil }
        do {
            try ArgAllowlist.validate(args)
        } catch let error as ArgAllowlistError {
            throw ConfigError(keyPath: path(key), reason: error.description)
        }
        return args
    }

    func stringTable(named key: String) throws -> [String: String]? {
        guard let value = table[key] else { return nil }
        guard let child = value.table else { throw ConfigError(keyPath: path(key), reason: "expected a table") }
        var result: [String: String] = [:]
        for name in child.keys {
            guard let entry = child[name]?.string else {
                throw ConfigError(keyPath: "\(path(key)).\(name.tomlKeyPathSegment)", reason: "expected a string")
            }
            result[name] = entry
        }
        return result
    }
}
