import AppKit
import BarnataCore
import Combine
import Foundation
import UniformTypeIdentifiers

/// The parts of the app the settings window drives but does not own
@MainActor
public struct SettingsActions {
    public var installDriver: (@escaping (CommandResult) -> Void) -> Void
    public var activateDriver: (@escaping (CommandResult) -> Void) -> Void
    public var stopKanata: (@escaping (CommandResult) -> Void) -> Void
    public var setDockIconVisible: (Bool) -> Void
    public var showUpdate: () -> Void
    /// Called after the window writes config.toml, with the modification date the watcher should ignore
    public var configDidChange: (Date?) -> Void

    public init(
        installDriver: @escaping (@escaping (CommandResult) -> Void) -> Void,
        activateDriver: @escaping (@escaping (CommandResult) -> Void) -> Void,
        stopKanata: @escaping (@escaping (CommandResult) -> Void) -> Void,
        setDockIconVisible: @escaping (Bool) -> Void,
        showUpdate: @escaping () -> Void,
        configDidChange: @escaping (Date?) -> Void
    ) {
        self.installDriver = installDriver
        self.activateDriver = activateDriver
        self.stopKanata = stopKanata
        self.setDockIconVisible = setDockIconVisible
        self.showUpdate = showUpdate
        self.configDidChange = configDidChange
    }
}

public enum SettingsTab: String, CaseIterable, Sendable {
    case general
    case configs

    public var title: String {
        switch self {
        case .general: "General"
        case .configs: "Configs"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .configs: "keyboard"
        }
    }
}

/// One config file reference, which is one `[presets."Name"]` table
public struct ConfigEntry: Identifiable, Equatable {
    public var name: String
    public var path: String
    public var layerIcons: [String: String]
    public var autorun: Bool
    public var isMissing: Bool

    public var id: String { name }

    public var invalidIconLayers: [String] { LayerSymbol.unavailable(in: layerIcons) }

    public var hasInvalidIcons: Bool { !invalidIconLayers.isEmpty }
}

/// Everything the settings window shows, read from and written back to config.toml
@MainActor
public final class SettingsModel: ObservableObject {
    public static let permissionPollInterval: TimeInterval = 2
    public static let uninstallConfirmationWord = "UNINSTALL"

    @Published public var tab: SettingsTab = .general
    @Published public var entries: [ConfigEntry] = []
    @Published public var selection: ConfigEntry.ID?
    @Published public var layers: [String] = []
    @Published public var configError: String?
    @Published public var errorMessage: String?

    @Published public var launchAtLogin = false
    @Published public var showDockIcon = false
    @Published public var checkForUpdates = true
    @Published public var availableUpdate: AvailableUpdate?
    @Published public var isUpdating = false
    @Published public var daemonApproved = false
    @Published public var hasAccessibility = false
    @Published public var driver: DriverStatus?
    @Published public var activePresetName: String?
    @Published public var isUninstalling = false

    public let configURL: URL

    private let setup: SetupActions
    private let actions: SettingsActions
    private var config: Config?
    private var pollTimer: Timer?

    public init(configURL: URL, setup: SetupActions, actions: SettingsActions) {
        self.configURL = configURL
        self.setup = setup
        self.actions = actions
        reload()
        refreshSystemState()
    }

    public var selectedEntry: ConfigEntry? {
        entries.first { $0.id == selection }
    }

    public var accessibilityPaneName: String { SystemPaneNames.accessibility }

    private var uninstaller: Uninstaller { Uninstaller(setup: setup, configURL: configURL) }

    // MARK: - Loading

    public func reload() {
        do {
            let loaded = try ConfigLoader.load(from: configURL)
            config = loaded
            configError = nil
            entries = loaded.presets.map { preset in
                ConfigEntry(
                    name: preset.name,
                    path: preset.configPath,
                    layerIcons: preset.layerIcons,
                    autorun: preset.autorun,
                    isMissing: !FileManager.default.fileExists(atPath: preset.configPath)
                )
            }
        } catch {
            configError = "\(error)"
        }

        if selection == nil || !entries.contains(where: { $0.id == selection }) {
            selection = entries.first?.id
        }
        refreshSelectionDetails()
    }

    public func selectionDidChange() {
        refreshSelectionDetails()
    }

    public func refreshSelectionDetails() {
        guard let entry = selectedEntry else {
            layers = []
            return
        }
        layers = KanataConfigScanner.layers(in: URL(fileURLWithPath: entry.path))
    }

    // MARK: - System state

    public func refreshSystemState() {
        daemonApproved = setup.isDaemonApproved
        hasAccessibility = setup.hasAccessibility
        launchAtLogin = setup.isLaunchAtLoginEnabled
        showDockIcon = config?.app.showDockIcon ?? false
        checkForUpdates = config?.app.checkForUpdates ?? true
    }

    public func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: SettingsModel.permissionPollInterval,
            repeats: true
        ) { _ in
            MainActor.assumeIsolated { self.refreshSystemState() }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Config files

    /// Adds a reference to the chosen file. Nothing is copied into the Barnata folder.
    public func addConfigFile() {
        let panel = NSOpenPanel()
        panel.title = "Add a kanata config file"
        panel.prompt = "Add"
        panel.message = "Barnata stores a reference to the file. The file is not copied or moved."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "kbd"), .plainText, .text].compactMap { $0 }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url)
    }

    public func add(_ url: URL) {
        let name = SettingsModel.uniqueName(from: url, taken: Set(entries.map(\.name)))
        apply { ConfigWriter.addPreset(name, configPath: url.standardizedFileURL.path, to: &$0) }
        selection = name
        selectionDidChange()
    }

    public func rename(_ entry: ConfigEntry, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else { return }
        guard !entries.contains(where: { $0.name == trimmed }) else {
            errorMessage = "Another config is already named \(trimmed)."
            return
        }
        apply { ConfigWriter.renamePreset(entry.name, to: trimmed, in: &$0) }
        selection = trimmed
        selectionDidChange()
    }

    /// Deletes the reference only. The kanata file itself is left where it is.
    public func delete(_ entry: ConfigEntry) {
        if activePresetName == entry.name { actions.stopKanata { _ in } }
        apply { ConfigWriter.removePreset(entry.name, from: &$0) }
        selection = entries.first?.id
        selectionDidChange()
    }

    public func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    nonisolated static func uniqueName(from url: URL, taken: Set<String>) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let base = stem.isEmpty ? "Config" : stem
        guard taken.contains(base) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }

    // MARK: - Layer icons

    public func icon(for layer: String, in entry: ConfigEntry) -> String? {
        entry.layerIcons[layer]
    }

    public func setIcon(_ symbol: String?, for layer: String, in entry: ConfigEntry) {
        apply { document in
            ConfigWriter.setLayerIcon(
                preset: entry.name,
                layer: layer,
                symbol: symbol,
                inherited: entry.layerIcons,
                in: &document
            )
        }
    }

    // MARK: - Setup

    public func approveDaemon() {
        setup.registerDaemon()
        setup.openLoginItems()
        refreshSystemState()
    }

    public func grantAccessibility() {
        setup.requestAccessibility()
        if !setup.hasAccessibility { setup.openAccessibility() }
        refreshSystemState()
    }

    public func installDriver() {
        actions.installDriver { [weak self] result in
            guard let self else { return }
            if result.ok { setup.openDriverExtensions() } else { errorMessage = result.message }
        }
    }

    public func activateDriver() {
        actions.activateDriver { [weak self] result in
            guard let self else { return }
            if result.ok { setup.openDriverExtensions() } else { errorMessage = result.message }
        }
    }

    public func setLaunchAtLogin(_ value: Bool) {
        guard setup.setLaunchAtLogin(value) else {
            errorMessage = "Cannot change the login item."
            launchAtLogin = setup.isLaunchAtLoginEnabled
            return
        }
        apply { $0.set(.bool(value), forKey: ConfigWriter.Key.launchAtLogin.rawValue, inTable: [ConfigWriter.tableName]) }
        launchAtLogin = setup.isLaunchAtLoginEnabled
    }

    public func setCheckForUpdates(_ value: Bool) {
        apply { $0.set(.bool(value), forKey: ConfigWriter.Key.checkForUpdates.rawValue, inTable: [ConfigWriter.tableName]) }
        checkForUpdates = value
    }

    public func showUpdate() {
        actions.showUpdate()
    }

    public func setShowDockIcon(_ value: Bool) {
        apply { $0.set(.bool(value), forKey: ConfigWriter.Key.showDockIcon.rawValue, inTable: [ConfigWriter.tableName]) }
        showDockIcon = value
        actions.setDockIconVisible(value)
    }

    // MARK: - Uninstall

    public func uninstall() {
        isUninstalling = true
        actions.stopKanata { [weak self] _ in
            guard let self else { return }
            uninstaller.run { error in
                if let error {
                    self.isUninstalling = false
                    self.errorMessage = error
                }
            }
        }
    }

    // MARK: - Writing

    private func apply(_ body: (inout TOMLDocument) -> Void) {
        do {
            let modified = try ConfigFileWriter(url: configURL).edit(body)
            actions.configDidChange(modified)
            errorMessage = nil
        } catch {
            errorMessage = "Cannot write \(configURL.lastPathComponent): \(error.localizedDescription)"
        }
        reload()
    }
}
