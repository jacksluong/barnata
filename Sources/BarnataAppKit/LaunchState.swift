import Foundation

/// What Barnata remembers between launches, so a bundle swapped underneath a running app,
/// which is what a Homebrew upgrade does, comes back on the preset it was running.
public struct LaunchState {
    private enum Key {
        static let preset = "lastRunningPreset"
        static let version = "lastAppVersion"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The preset to pick back up, non-nil only when the bundle changed since the last launch
    public func presetToResume(currentVersion: String) -> String? {
        guard let recorded = defaults.string(forKey: Key.version), recorded != currentVersion else { return nil }
        return defaults.string(forKey: Key.preset)
    }

    public func recordLaunch(version: String) {
        defaults.set(version, forKey: Key.version)
    }

    public func recordRunningPreset(_ name: String?) {
        guard let name else { return defaults.removeObject(forKey: Key.preset) }
        defaults.set(name, forKey: Key.preset)
    }
}
