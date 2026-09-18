import Foundation

public struct Config: Sendable, Equatable {
    public var app: AppSettings
    public var defaults: PresetDefaults
    public var presets: [Preset]

    public init(app: AppSettings = AppSettings(), defaults: PresetDefaults = PresetDefaults(), presets: [Preset] = []) {
        self.app = app
        self.defaults = defaults
        self.presets = presets
    }

    public var autorunPreset: Preset? { presets.first { $0.autorun } }

    public func preset(named name: String) -> Preset? { presets.first { $0.name == name } }
}

public struct AppSettings: Sendable, Equatable {
    public var launchAtLogin: Bool?
    public var showDockIcon: Bool
    public var statusIcons: String?

    public init(launchAtLogin: Bool? = nil, showDockIcon: Bool = false, statusIcons: String? = nil) {
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
        self.statusIcons = statusIcons
    }
}

public struct PresetDefaults: Sendable, Equatable {
    public var autorestartOnCrash: Bool
    public var extraArgs: [String]
    public var layerIcons: [String: String]

    public init(
        autorestartOnCrash: Bool = false,
        extraArgs: [String] = [],
        layerIcons: [String: String] = [:]
    ) {
        self.autorestartOnCrash = autorestartOnCrash
        self.extraArgs = extraArgs
        self.layerIcons = layerIcons
    }
}

public struct Preset: Sendable, Equatable {
    public static let layerIconFallbackKey = "*"

    public var name: String
    public var configPath: String
    public var autorun: Bool
    public var autorestartOnCrash: Bool
    public var extraArgs: [String]
    public var layerIcons: [String: String]

    public init(
        name: String,
        configPath: String,
        autorun: Bool = false,
        autorestartOnCrash: Bool = false,
        extraArgs: [String] = [],
        layerIcons: [String: String] = [:]
    ) {
        self.name = name
        self.configPath = configPath
        self.autorun = autorun
        self.autorestartOnCrash = autorestartOnCrash
        self.extraArgs = extraArgs
        self.layerIcons = layerIcons
    }

    public var startRequest: StartRequest {
        StartRequest(
            presetName: name,
            configPath: configPath,
            extraArgs: extraArgs,
            autorestartOnCrash: autorestartOnCrash
        )
    }

    /// SF Symbol name for a layer, falling back to the `*` entry
    public func iconSymbol(forLayer layer: String) -> String? {
        layerIcons[layer] ?? layerIcons[Preset.layerIconFallbackKey]
    }
}
