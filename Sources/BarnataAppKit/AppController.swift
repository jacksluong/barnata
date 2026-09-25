import AppKit
import BarnataCore
import Foundation

/// Owns every moving part of the app: config, daemon connection, kanata connection, and the menu.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    public static let setupPollInterval: TimeInterval = 5
    public static let reloadFlashDuration: TimeInterval = 2
    /// How long quitting waits for the daemon to confirm before leaving anyway
    public static let quitTimeout: TimeInterval = 5
    /// Failed connections to an approved daemon before its launchd job is rebuilt
    public static let repairAfterFailures = 3
    /// Rebuilds attempted per launch, so a registration that cannot be fixed stops churning
    public static let maxRegistrationRepairs = 3

    private let setup = SetupActions()
    private let statusItem = StatusItemController()
    private let daemonClient = DaemonClient()
    private let tcpClient = KanataTCPClient()
    private let configURL: URL
    private let watcher: ConfigWatcher
    private let launchState = LaunchState()
    private let updateChecker = UpdateChecker(currentVersion: AppBundle.shortVersion)

    private var state = MenuState()
    private var config: Config?
    private var settings: SettingsWindowController?
    private var bundledKanataVersion: String?
    private var setupTimer: Timer?
    private var reloadTimer: Timer?

    private var didRunUpdateFlow = false
    private var isRestartingDaemonForUpdate = false
    private var didAttemptAutostart = false
    private var isShuttingDownForQuit = false
    private var didReplyToTerminate = false
    private var quitTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var didCheckKanataVersion = false
    private var presetToStartAfterUpdate: String?
    private var isDaemonConnected = false
    private var registrationRepairs = 0

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
        NSApp.mainMenu = MainMenu.make()

        presetToStartAfterUpdate = launchState.presetToResume(currentVersion: state.appVersion)
        launchState.recordLaunch(version: state.appVersion)

        updateChecker.onChange = { [weak self] update in self?.updateDidChange(update) }
        // A bare executable is not a bundle Homebrew can upgrade, so it is never offered one
        if AppBundle.bundleURL != nil { updateChecker.start() }
        loadConfig()
        applyAppSettings()

        statusItem.onAction = { [weak self] action in self?.perform(action) }
        statusItem.onMenuWillOpen = { [weak self] in self?.refreshOnMenuOpen() }

        watcher.onChange = onMain { [weak self] in self?.configFileDidChange() }
        watcher.start()

        daemonClient.onEvent = onMain { [weak self] event in self?.handle(daemonEvent: event) }
        tcpClient.onEvent = onMain { [weak self] event in self?.handle(kanataEvent: event) }

        installTerminationSignalHandlers()
        setup.registerDaemon()
        refreshSetupState()
        daemonClient.start()
        loadBundledKanataVersion()
        render()
        reportLastUpdate()
    }

    /// The app has no main window, so a Dock click opens or raises the settings window
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Quitting takes kanata and the daemon with it, and waits for them to be gone, so the
    /// keyboard is never left remapped by an absent app
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShuttingDownForQuit else { return .terminateNow }
        isShuttingDownForQuit = true

        daemonClient.shutdownDaemon(onMain { [weak self] result in
            if !result.ok { log.error("daemon shutdown on quit failed: \(result.message ?? "", privacy: .public)") }
            self?.finishTerminating()
        })
        quitTimer = Timer.scheduledTimer(withTimeInterval: AppController.quitTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                log.error("the daemon did not confirm its shutdown, quitting anyway")
                self?.finishTerminating()
            }
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        tcpClient.disconnect()
        daemonClient.stop()
    }

    private func finishTerminating() {
        guard !didReplyToTerminate else { return }
        didReplyToTerminate = true
        quitTimer?.invalidate()
        quitTimer = nil
        // Stops the reconnect backoff from waking launchd and starting a fresh daemon
        daemonClient.stop()
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// AppKit runs no terminate path for the signals that pkill, kill, and logout send
    private func installTerminationSignalHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Daemon

    private func handle(daemonEvent event: DaemonClient.Event) {
        switch event {
        case .connected(let daemonVersion):
            handleDaemonConnected(daemonVersion: daemonVersion)
        case .status(let status):
            apply(status)
        case .disconnected:
            isDaemonConnected = false
            state.status = nil
            // A daemon that died before it could start the preset should be retried on reconnect
            didAttemptAutostart = false
            tcpClient.disconnect()
            clearLayers()
            render()
        case .unreachable(let attempts):
            repairDaemonRegistration(after: attempts)
        }
    }

    /// Update flow: a daemon from an older bundle is shut down so launchd starts the new binary
    private func handleDaemonConnected(daemonVersion: String) {
        isDaemonConnected = true
        registrationRepairs = 0
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
            // Keeps the preset the last launch recorded when this daemon has nothing running
            presetToStartAfterUpdate = (status?.state == .running ? status?.presetName : nil)
                ?? presetToStartAfterUpdate
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

    /// A Homebrew upgrade used to run `launchctl remove` on the daemon, which drops the launchd
    /// job while `SMAppService` still reports it enabled, so nothing short of re-registering
    /// brings the Mach service back.
    private func repairDaemonRegistration(after attempts: Int) {
        guard registrationRepairs < AppController.maxRegistrationRepairs, !isShuttingDownForQuit else { return }
        guard attempts >= AppController.repairAfterFailures, setup.isDaemonApproved else { return }
        registrationRepairs += 1
        log.notice("the daemon is approved but unreachable after \(attempts) attempts, re-registering it")

        setup.repairDaemonRegistration { [weak self] error in
            guard let self else { return }
            state.lastActionError = error
            refreshSetupState()
            daemonClient.reconnect()
            render()
        }
    }

    private func apply(_ status: DaemonStatus) {
        state.status = status
        // The idle status a quit or an update restart pushes is not the user's choice to stop
        if !isShuttingDownForQuit, !isRestartingDaemonForUpdate {
            launchState.recordRunningPreset(status.state == .running ? status.presetName : nil)
        }

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

        guard status.state == .idle else {
            didAttemptAutostart = true
            return
        }
        // A preset that is missing because the config is broken is worth another try once it is fixed
        let name = presetToStartAfterUpdate ?? config?.autorunPreset?.name
        guard let name, let preset = config?.preset(named: name) else { return }
        presetToStartAfterUpdate = nil
        didAttemptAutostart = true
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
        settings?.model.reload()
        if let status = state.status { autostartIfNeeded(status) }
        render()
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
        // The backoff climbs to 30 s, and an open menu is the moment the user wants it retried
        if !isDaemonConnected { daemonClient.reconnect() }
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

        case .showUpdate:
            updateChecker.check { [weak self] _ in self?.offerUpdate() }

        case .openKanataLog:
            setup.open(AppBundle.kanataLogURL)

        case .openPreferences:
            showSettings()

        case .quit:
            NSApp.terminate(nil)
        }
        render()
    }

    // MARK: - Updates

    private func updateDidChange(_ update: AvailableUpdate?) {
        state.availableUpdate = update
        if let update { log.notice("barnata \(update.version, privacy: .public) is available") }
        render()
    }

    private func offerUpdate() {
        guard let update = state.availableUpdate, !state.isUpdating else { return }
        guard let bundle = AppBundle.bundleURL else { return }
        guard UpdatePrompt.ask(about: update, currentVersion: AppBundle.shortVersion) == .update else { return }

        if let message = UpdateInstaller.start(appBundle: bundle) {
            log.error("cannot start the update: \(message, privacy: .public)")
            UpdatePrompt.reportFailure(message)
            return
        }

        state.isUpdating = true
        render()
        // Homebrew waits for this to finish before it touches the bundle, and opens the new one after
        NSApp.terminate(nil)
    }

    /// Homebrew ran while the app was gone, so its exit code is read back on the next launch
    private func reportLastUpdate() {
        guard let code = UpdateInstaller.takeResult(), code != 0 else { return }
        log.error("the last update exited with \(code)")
        UpdatePrompt.reportFailure(
            "Homebrew exited with code \(code). The output is in \(UpdateInstaller.logURL.abbreviatedPath)."
        )
    }

    // MARK: - Settings window

    private func showSettings() {
        let controller = settings ?? SettingsWindowController(model: makeSettingsModel())
        settings = controller
        controller.model.driver = state.driver
        controller.model.activePresetName = state.activePresetName
        controller.model.availableUpdate = state.availableUpdate
        controller.model.isUpdating = state.isUpdating
        controller.show()
    }

    private func makeSettingsModel() -> SettingsModel {
        SettingsModel(
            configURL: configURL,
            setup: setup,
            actions: SettingsActions(
                installDriver: { [weak self] completion in
                    self?.daemonClient.installDriver(onMain { result in
                        self?.report(result, action: "install the Karabiner driver")
                        completion(result)
                    })
                },
                activateDriver: { [weak self] completion in
                    self?.daemonClient.activateDriver(onMain { result in
                        self?.report(result, action: "activate the Karabiner driver")
                        completion(result)
                    })
                },
                stopKanata: { [weak self] completion in
                    self?.daemonClient.stopKanata(onMain { result in
                        self?.report(result, action: "stop kanata")
                        completion(result)
                    })
                },
                setDockIconVisible: { [weak self] visible in
                    self?.state.showDockIcon = visible
                    self?.config?.app.showDockIcon = visible
                    self?.statusItem.setDockIconVisible(visible)
                },
                showUpdate: { [weak self] in self?.offerUpdate() },
                checkForUpdates: { [weak self] completion in
                    guard let self, AppBundle.bundleURL != nil else { return completion(nil) }
                    updateChecker.check(completion: completion)
                },
                configDidChange: { [weak self] modified in
                    guard let self else { return }
                    watcher.ignoreChange(modifiedAt: modified)
                    loadConfig()
                    applyAppSettings()
                    render()
                }
            )
        )
    }

    // MARK: - Rendering

    private func render() {
        let preset = state.activePresetName.flatMap { config?.preset(named: $0) }
        settings?.model.driver = state.driver
        settings?.model.activePresetName = state.activePresetName
        settings?.model.availableUpdate = state.availableUpdate
        settings?.model.isUpdating = state.isUpdating
        statusItem.render(state, preset: preset)
    }
}
