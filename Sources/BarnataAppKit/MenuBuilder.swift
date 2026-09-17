import BarnataCore
import Foundation

/// Turns a `MenuState` into the menu tree from 01-architecture.md
public enum MenuBuilder {
    public static func entries(for state: MenuState) -> [MenuEntry] {
        var entries: [MenuEntry] = [.label("Barnata: \(state.title)")]
        entries.append(contentsOf: state.detailLines.map(MenuEntry.label))
        entries.append(.separator)
        entries.append(contentsOf: presets(state))
        entries.append(contentsOf: kanataControls(state))
        entries.append(.separator)
        entries.append(contentsOf: files(state))
        entries.append(.separator)
        // Quitting always stops kanata, so no shortcut that could be hit by accident
        entries.append(.item(MenuItem(title: "Quit Barnata", action: .quit)))
        return entries
    }

    private static func presets(_ state: MenuState) -> [MenuEntry] {
        guard !state.presetNames.isEmpty else {
            return [.item(MenuItem(title: "No presets in config.toml", isEnabled: false))]
        }

        return [.label("Configs")] + state.presetNames.map { name in
            let isActive = state.activePresetName == name
            return .item(MenuItem(
                title: name,
                action: isActive ? .stopKanata : .startPreset(name),
                isEnabled: state.canControlKanata && state.configError == nil,
                isChecked: isActive,
                isIndented: true
            ))
        }
    }

    private static func kanataControls(_ state: MenuState) -> [MenuEntry] {
        var entries: [MenuEntry] = []

        if state.isRunning, !state.layers.isEmpty {
            entries.append(.submenu(
                MenuItem(title: "Layers", isEnabled: state.canControlKanata),
                state.layers.map { layer in
                    .item(MenuItem(
                        title: layer,
                        action: .switchLayer(layer),
                        isEnabled: state.canControlKanata,
                        isChecked: layer == state.currentLayer
                    ))
                }
            ))
        }

        let liveControls = state.canControlKanata && state.isRunning
        entries.append(.item(MenuItem(
            title: "Reload config",
            action: .reloadConfig,
            isEnabled: liveControls,
            keyEquivalent: "r"
        )))

        if state.activePresetSupportsCycling {
            entries.append(.item(MenuItem(title: "Next config file", action: .nextConfigFile, isEnabled: liveControls)))
            entries.append(.item(MenuItem(title: "Previous config file", action: .previousConfigFile, isEnabled: liveControls)))
        }

        entries.append(.item(MenuItem(title: "Restart kanata", action: .restartKanata, isEnabled: liveControls)))
        entries.append(.item(MenuItem(
            title: "Stop kanata",
            action: .stopKanata,
            isEnabled: state.daemonApproved && state.state != .idle
        )))
        return entries
    }

    private static func files(_ state: MenuState) -> [MenuEntry] {
        [
            .item(MenuItem(title: "Open kanata log", action: .openKanataLog)),
            .item(MenuItem(title: "Preferences…", action: .openPreferences, keyEquivalent: ",")),
        ]
    }
}
