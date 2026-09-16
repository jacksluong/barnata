import AppKit
import BarnataCore
import Foundation

/// Owns every moving part of the app: config, daemon connection, kanata connection, and the menu.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    public static let setupPollInterval: TimeInterval = 5
    public static let reloadFlashDuration: TimeInterval = 2

    private let setup = SetupActions()
    private let statusItem = StatusItemController()
    private let daemonClient = DaemonClient()
    private let tcpClient = KanataTCPClient()
    private let configURL: URL
    private let watcher: ConfigWatcher

    private var state = MenuState()
    private var config: Config?
    private var bundledKanataVersion: String?
    private var setupTimer: Timer?
    private var reloadTimer: Timer?

    private var didRunUpdateFlow = false
    private var isRestartingDaemonForUpdate = false
    private var didAttemptAutostart = false
    private var isStoppingKanataForQuit = false
    private var didCheckKanataVersion = false
    private var presetToStartAfterUpdate: String?

    public override init() {
        configURL = ConfigLoader.defaultURL()
        watcher = ConfigWatcher(url: configURL)
        super.init()
    }

    // MARK: - Startup sequence from 01-architecture.md

    public func applicationDidFinishLaunching(_ notification: Notification) {
        state.appVersion = AppBundle.version
        state.currentUID = getuid()
        state.configPath = configURL.path

        loadConfig()
        applyAppSettings()

        statusItem.onAction = { [weak self] action in self?.perform(action) }
        statusItem.onMenuWillOpen = { [weak self] in self?.refreshOnMenuOpen() }

        watcher.onChange = onMain { [weak self] in self?.configFileDidChange() }
        watcher.start()

        daemonClient.onEvent = onMain { [weak self] event in self?.handle(daemonEvent: event) }
        tcpClient.onEvent = onMain { [weak self] event in self?.handle(kanataEvent: event) }

        setup.registerDaemon()
        refreshSetupState()
        daemonClient.start()
        loadBundledKanataVersion()
        render()
    }

    /// Quitting always stops kanata, so the keyboard is never left remapped by an absent app
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isStoppingKanataForQuit else { return .terminateNow }
        isStoppingKanataForQuit = true
        daemonClient.stopKanata(onMain { result in
            if !result.ok { log.error("stop kanata on quit failed: \(result.message ?? "", privacy: .public)") }
            NSApp.reply(toApplicationShouldTerminate: true)
        })
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        tcpClient.disconnect()
        daemonClient.stop()
    }

    // MARK: - Daemon

    private func handle(daemonEvent event: DaemonClient.Event) {
        switch event {
        case .connected(let daemonVersion):
            handleDaemonConnected(daemonVersion: daemonVersion)
        case .status(let status):
            apply(status)
        case .disconnected:
            state.status = nil
            // A daemon that died before it could start the preset should be retried on reconnect
            didAttemptAutostart = false
            tcpClient.disconnect()
            clearLayers()
            render()
        }
    }

    /// Update flow: a daemon from an older bundle is shut down so launchd starts the new binary
    private func handleDaemonConnected(daemonVersion: String) {
        if isRestartingDaemonForUpdate {
            // launchd started the new binary; it has no children, so autorun applies again
            isRestartingDaemonForUpdate = false
            didAttemptAutostart = false
            refreshStatus()
            return
        }
        guard !didRunUpdateFlow, daemonVersion != state.appVersion else {
            didRunUpdateFlow = true
            refreshStatus()
            return
        }
        didRunUpdateFlow = true
        isRestartingDaemonForUpdate = true
        log.notice("daemon is \(daemonVersion, privacy: .public), app is \(self.state.appVersion, privacy: .public), restarting it")

        daemonClient.status(onMain { [weak self] status in
            guard let self else { return }
            presetToStartAfterUpdate = status?.state == .running ? status?.presetName : nil
            daemonClient.stopKanata(onMain { [weak self] _ in
                guard let self else { return }
                daemonClient.shutdownDaemon(onMain { [weak self] _ in
                    self?.daemonClient.reconnect()
                })
            })
        })
    }

    private func refreshStatus() {
        daemonClient.status(onMain { [weak self] status in
            guard let self, let status else { return }
            apply(status)
        })
    }

    private func apply(_ status: DaemonStatus) {
        state.status = status
        state.activePresetSupportsCycling = status.configPaths.count > 1

        if status.state == .running, !state.isRunningForAnotherUser, let port = status.tcpPort {
            tcpClient.connect(port: port)
        } else {
            tcpClient.disconnect()
            clearLayers()
        }

        restartIfKanataIsStale(status)
        autostartIfNeeded(status)
        render()
    }

    /// The bundle ships one kanata; a running copy from an older bundle is replaced once per launch
    private func restartIfKanataIsStale(_ status: DaemonStatus) {
        guard !didCheckKanataVersion, status.state == .running else { return }
        guard let bundled = bundledKanataVersion, let running = status.kanataVersion else { return }
        didCheckKanataVersion = true
        guard bundled != running else { return }

        log.notice("kanata \(running, privacy: .public) is running but the bundle ships \(bundled, privacy: .public)")
        daemonClient.restartKanata(onMain { [weak self] result in self?.report(result, action: "restart kanata") })
    }

    private func autostartIfNeeded(_ status: DaemonStatus) {
        // Starting into a daemon that is about to be shut down for the update just fails
        guard !didAttemptAutostart, state.daemonApproved, !isRestartingDaemonForUpdate else { return }
        // kanata exits 1 on every attempt without the grant, so wait for it rather than churn
        guard state.missingPermission == nil else { return }
        didAttemptAutostart = true

        guard status.state == .idle else { return }
        let name = presetToStartAfterUpdate ?? config?.autorunPreset?.name
        presetToStartAfterUpdate = nil
        guard let name, let preset = config?.preset(named: name) else { return }
        start(preset)
    }

    private func start(_ preset: Preset) {
        state.lastActionError = nil
        daemonClient.start(preset.startRequest, completion: onMain { [weak self] result in
            self?.report(result, action: "start \(preset.name)")
        })
    }

    private func report(_ result: CommandResult, action: String) {
        if result.ok {
            state.lastActionError = nil
        } else {
            let message = result.message ?? "the daemon refused the request"
            log.error("\(action, privacy: .public) failed: \(message, privacy: .public)")
            state.lastActionError = message
        }
        render()
        refreshStatus()
    }

    // MARK: - kanata TCP

    private func handle(kanataEvent event: KanataTCPClient.Event) {
        switch event {
        case .connected:
            state.lastReloadError = nil
        case .message(let message):
            apply(message)
        case .disconnected:
            clearLayers()
        }
        render()
    }

    private func apply(_ message: KanataServerMessage) {
        switch message {
        case .layerNames(let names):
            state.layers = names
        case .layerChange(let layer), .currentLayerName(let layer):
            state.currentLayer = layer
            if !state.layers.contains(layer) { tcpClient.send(.requestLayerNames) }
        case .configFileReload:
            state.lastReloadError = nil
            flashReloading()
        case .reloadResult(let ok, let message):
            state.lastReloadError = ok ? nil : (message ?? "kanata rejected the config")
            if ok { flashReloading() }
        case .error(let text):
            state.lastReloadError = text
        case .helloOk, .ignored:
            break
        }
    }

    private func clearLayers() {
        state.layers = []
        state.currentLayer = nil
    }

    private func flashReloading() {
        state.isReloading = true
        reloadTimer?.invalidate()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: AppController.reloadFlashDuration, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.state.isReloading = false
                self.render()
            }
        }
    }

    // MARK: - Config

    private func loadConfig() {
        do {
            let loaded = try ConfigLoader.load(from: configURL)
            config = loaded
            state.configError = nil
            state.presetNames = loaded.presets.map(\.name)
            statusItem.resolver = IconResolver(config: loaded, configURL: configURL)
        } catch {
            // Keep the last good config so icons and preset names survive a broken edit
            log.error("config error: \(String(describing: error), privacy: .public)")
            state.configError = "\(error)"
        }
    }

    private func applyAppSettings() {
        guard let config else { return }
        state.showDockIcon = config.app.showDockIcon
        statusItem.setDockIconVisible(config.app.showDockIcon)
        if let wanted = config.app.launchAtLogin, wanted != setup.isLaunchAtLoginEnabled {
            setup.setLaunchAtLogin(wanted)
        }
        state.launchAtLogin = setup.isLaunchAtLoginEnabled
    }

    private func configFileDidChange() {
        log.info("config file changed, reloading")
        loadConfig()
        applyAppSettings()
        render()
    }

    private func write(_ key: ConfigWriter.Key, value: Bool) -> Bool {
        do {
            let modified = try ConfigFileWriter(url: configURL).set(key, to: value)
            watcher.ignoreChange(modifiedAt: modified)
            state.lastActionError = nil
            return true
        } catch {
            state.lastActionError = "cannot write \(configURL.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Daemon approval and privacy permissions

    /// System Settings changes arrive with no notification, so poll while anything is outstanding
    private func refreshSetupState() {
        let approved = setup.isDaemonApproved
        let approvalChanged = approved != state.daemonApproved
        state.daemonApproved = approved

        let hadPermission = state.missingPermission == nil
        state.hasAccessibility = setup.hasAccessibility

        if approvalChanged { daemonClient.reconnect() }
        // A grant that just landed is the reason kanata was crashing, so try it again
        if !hadPermission, state.missingPermission == nil, state.state != .running {
            didAttemptAutostart = false
            refreshStatus()
        }

        if approved, state.missingPermission == nil {
            setupTimer?.invalidate()
            setupTimer = nil
        } else if setupTimer == nil {
            setupTimer = Timer.scheduledTimer(
                withTimeInterval: AppController.setupPollInterval,
                repeats: true
            ) { _ in
                MainActor.assumeIsolated {
                    self.refreshSetupState()
                    self.render()
                }
            }
        }
    }

    private func refreshOnMenuOpen() {
        refreshSetupState()
        refreshStatus()
        render()
    }

    private func loadBundledKanataVersion() {
        DispatchQueue.global(qos: .utility).async {
            let version = AppBundle.kanataVersion()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.bundledKanataVersion = version }
            }
        }
    }

    // MARK: - Menu actions

    private func perform(_ action: MenuAction) {
        switch action {
        case .none:
            break

        case .startPreset(let name):
            guard let preset = config?.preset(named: name) else { return }
            start(preset)

        case .stopKanata:
            daemonClient.stopKanata(onMain { [weak self] result in self?.report(result, action: "stop kanata") })

        case .restartKanata:
            daemonClient.restartKanata(onMain { [weak self] result in self?.report(result, action: "restart kanata") })

        case .switchLayer(let layer):
            tcpClient.send(.changeLayer(layer))

        case .reloadConfig:
            tcpClient.send(.reload)

        case .nextConfigFile:
            tcpClient.send(.reloadNext)

        case .previousConfigFile:
            tcpClient.send(.reloadPrevious)

        case .openConfigFile:
            setup.open(configURL)

        case .openKanataLog:
            setup.open(AppBundle.kanataLogURL)

        case .approveDaemon:
            setup.registerDaemon()
            setup.openLoginItems()
            refreshSetupState()

        case .installDriver:
            daemonClient.installDriver(onMain { [weak self] result in
                guard let self else { return }
                report(result, action: "install the Karabiner driver")
                if result.ok { setup.openDriverExtensions() }
            })

        case .activateDriver:
            daemonClient.activateDriver(onMain { [weak self] result in
                guard let self else { return }
                report(result, action: "activate the Karabiner driver")
                if result.ok { setup.openDriverExtensions() }
            })

        case .grantAccessibility:
            // The request is what puts Barnata in the pane, so always make it, then send
            // the user to the toggle. When the state is undetermined it also prompts.
            setup.requestAccessibility()
            if !setup.hasAccessibility { setup.openAccessibility() }

        case .toggleLaunchAtLogin:
            let value = !state.launchAtLogin
            guard setup.setLaunchAtLogin(value) else {
                state.lastActionError = "cannot change the login item"
                break
            }
            _ = write(.launchAtLogin, value: value)
            state.launchAtLogin = setup.isLaunchAtLoginEnabled
            config?.app.launchAtLogin = value

        case .toggleShowDockIcon:
            let value = !state.showDockIcon
            guard write(.showDockIcon, value: value) else { break }
            state.showDockIcon = value
            config?.app.showDockIcon = value
            statusItem.setDockIconVisible(value)

        case .quit:
            NSApp.terminate(nil)
        }
        render()
    }

    // MARK: - Rendering

    private func render() {
        let preset = state.activePresetName.flatMap { config?.preset(named: $0) }
        statusItem.render(state, preset: preset)
    }
}
