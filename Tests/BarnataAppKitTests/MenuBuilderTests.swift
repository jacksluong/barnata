import BarnataCore
import Foundation
import XCTest

@testable import BarnataAppKit

final class MenuTitleTests: XCTestCase {
    func testEveryTitleVariantFromTheArchitectureDoc() {
        var unapproved = readyState()
        unapproved.daemonApproved = false
        XCTAssertEqual(unapproved.title, "Daemon not approved")

        var broken = readyState()
        broken.configError = "presets.Default.kanata_config: required"
        XCTAssertEqual(broken.title, "Config error: presets.Default.kanata_config: required")

        let newerDriver = readyState(status: daemonStatus(driver: driverStatus(version: "8.1.0", requiredVersion: "6.8.0")))
        XCTAssertEqual(newerDriver.title, "Driver 8.1.0 is newer than required 6.8.0")

        let noDriver = readyState(status: daemonStatus(driver: driverStatus(installed: false, version: nil)))
        XCTAssertEqual(noDriver.title, "Driver not installed")

        let otherUser = readyState(status: daemonStatus(state: .running, presetName: "Default", ownerUID: otherUID))
        XCTAssertEqual(otherUser.title, "Running for another user")

        XCTAssertEqual(readyState(status: daemonStatus(state: .starting)).title, "Starting")
        XCTAssertEqual(readyState(status: daemonStatus(state: .stopping)).title, "Stopping")
        XCTAssertEqual(readyState(status: daemonStatus(state: .idle)).title, "Not running")
        XCTAssertEqual(
            readyState(status: daemonStatus(state: .crashed, lastExitCode: 3)).title,
            "Crashed (exit 3)"
        )
        XCTAssertEqual(runningState().title, "Running (canary.kbd, layer: base)")
        XCTAssertEqual(runningState(layer: nil).title, "Running (canary.kbd)")
    }

    func testAMissingGrantIsNamedInsteadOfTheExitCode() {
        var idle = readyState()
        idle.hasAccessibility = false
        XCTAssertEqual(idle.title, "\(SystemPaneNames.accessibility) not granted")
        XCTAssertEqual(idle.presentation, .status(.crashed))

        // kanata exits 1 when the grant is missing; the exit code explains nothing
        var crashed = readyState(status: daemonStatus(state: .crashed, lastExitCode: 1))
        crashed.hasAccessibility = false
        XCTAssertEqual(crashed.title, "\(SystemPaneNames.accessibility) not granted")
    }

    func testARunningKanataOutranksAStaleMissingGrant() {
        var running = runningState()
        running.hasAccessibility = false
        XCTAssertEqual(running.title, "Running (canary.kbd, layer: base)")
        XCTAssertEqual(running.presentation, .layer("base"))
    }

    func testTheDaemonAndDriverStillOutrankAMissingGrant() {
        var unapproved = readyState()
        unapproved.daemonApproved = false
        unapproved.hasAccessibility = false
        XCTAssertEqual(unapproved.title, "Daemon not approved")

        var noDriver = readyState(status: daemonStatus(driver: driverStatus(installed: false, version: nil)))
        noDriver.hasAccessibility = false
        XCTAssertEqual(noDriver.title, "Driver not installed")
    }

    func testCrashedStateAddsTheKanataErrorAsADetailLine() {
        let state = readyState(status: daemonStatus(
            state: .crashed,
            lastExitCode: 1,
            lastError: "parse error: unknown key\nsecond line"
        ))
        XCTAssertEqual(state.detailLines, ["parse error: unknown key"])
        XCTAssertEqual(MenuBuilder.entries(for: state).labels.first, "Barnata: Crashed (exit 1)")
    }

    func testAFailedReloadIsShownUnderTheTitle() {
        var state = runningState()
        state.lastReloadError = "config error at line 4"
        XCTAssertEqual(state.detailLines, ["Reload failed: config error at line 4"])
    }

    func testIconPriorityOrder() {
        var unapproved = runningState()
        unapproved.daemonApproved = false
        XCTAssertEqual(unapproved.presentation, .status(.crashed))

        var broken = runningState()
        broken.configError = "bad"
        XCTAssertEqual(broken.presentation, .status(.crashed))

        let noDriver = readyState(status: daemonStatus(state: .running, driver: driverStatus(installed: false, version: nil)))
        XCTAssertEqual(noDriver.presentation, .status(.crashed))

        XCTAssertEqual(readyState(status: daemonStatus(state: .crashed)).presentation, .status(.crashed))
        XCTAssertEqual(readyState(status: daemonStatus(state: .idle)).presentation, .status(.paused))

        var reloading = runningState()
        reloading.isReloading = true
        XCTAssertEqual(reloading.presentation, .status(.reloading))

        XCTAssertEqual(runningState().presentation, .layer("base"))
        XCTAssertEqual(runningState(layer: nil).presentation, .status(.normal))
    }

    func testTransitionsAreTheOnesThatGetASpinner() {
        XCTAssertTrue(readyState(status: daemonStatus(state: .starting)).isTransitioning)
        XCTAssertTrue(readyState(status: daemonStatus(state: .stopping)).isTransitioning)
        XCTAssertFalse(runningState().isTransitioning)
    }
}

final class MenuBuilderTests: XCTestCase {
    func testThePresetOfTheRunningKanataIsCheckedAndStopsIt() {
        let entries = MenuBuilder.entries(for: runningState())

        let active = entries.item(titled: "Default")
        XCTAssertEqual(active?.isChecked, true)
        XCTAssertEqual(active?.action, .stopKanata)

        let inactive = entries.item(titled: "Other")
        XCTAssertEqual(inactive?.isChecked, false)
        XCTAssertEqual(inactive?.action, .startPreset("Other"))
    }

    func testPresetsFollowConfigOrderAndAreIndentedUnderAHeader() {
        let entries = MenuBuilder.entries(for: runningState())
        XCTAssertTrue(entries.labels.contains("Presets"))
        XCTAssertEqual(entries.item(titled: "Default")?.isIndented, true)
    }

    func testTheCurrentLayerIsCheckedInTheLayersSubmenu() {
        let layers = MenuBuilder.entries(for: runningState()).submenu(titled: "Layers")
        XCTAssertEqual(layers?.allItems.map(\.title), ["base", "typing", "arrows"])
        XCTAssertEqual(layers?.item(titled: "base")?.isChecked, true)
        XCTAssertEqual(layers?.item(titled: "typing")?.isChecked, false)
        XCTAssertEqual(layers?.item(titled: "typing")?.action, .switchLayer("typing"))
    }

    func testTheLayersSubmenuIsAbsentWhenKanataIsNotRunning() {
        XCTAssertNil(MenuBuilder.entries(for: readyState()).submenu(titled: "Layers"))
    }

    func testConfigCyclingItemsOnlyAppearForAMultiFilePreset() {
        XCTAssertNil(MenuBuilder.entries(for: runningState()).item(titled: "Next config file"))

        var cycling = runningState()
        cycling.activePresetSupportsCycling = true
        let entries = MenuBuilder.entries(for: cycling)
        XCTAssertEqual(entries.item(titled: "Next config file")?.action, .nextConfigFile)
        XCTAssertEqual(entries.item(titled: "Previous config file")?.action, .previousConfigFile)
    }

    func testRunningForAnotherUserEnablesOnlyStop() {
        let state = readyState(status: daemonStatus(
            state: .running,
            presetName: "Default",
            configPaths: ["/Users/other/.config/kanata/canary.kbd"],
            tcpPort: 5829,
            ownerUID: otherUID
        ))
        let entries = MenuBuilder.entries(for: state)

        let kanataActions: Set<MenuAction> = [
            .stopKanata, .restartKanata, .reloadConfig, .startPreset("Default"), .startPreset("Other"),
        ]
        let enabled = Set(entries.enabledActions).intersection(kanataActions)
        XCTAssertEqual(enabled, [.stopKanata])
    }

    func testStopIsDisabledWhileIdleAndEnabledWhileRunning() {
        XCTAssertEqual(MenuBuilder.entries(for: readyState()).item(titled: "Stop kanata")?.isEnabled, false)
        XCTAssertEqual(MenuBuilder.entries(for: runningState()).item(titled: "Stop kanata")?.isEnabled, true)
    }

    func testABrokenConfigDisablesTheStartItems() {
        var state = readyState()
        state.configError = "unknown key"
        XCTAssertEqual(MenuBuilder.entries(for: state).item(titled: "Default")?.isEnabled, false)
    }

    func testAnEmptyConfigSaysSoInsteadOfShowingNothing() {
        var state = readyState()
        state.presetNames = []
        XCTAssertEqual(MenuBuilder.entries(for: state).item(titled: "No presets in config.toml")?.isEnabled, false)
    }

    func testReloadKeepsItsShortcutAndQuitHasNone() {
        let entries = MenuBuilder.entries(for: runningState())
        XCTAssertEqual(entries.item(titled: "Reload config")?.keyEquivalent, "r")
        XCTAssertEqual(entries.item(titled: "Quit Barnata")?.keyEquivalent, "")
        XCTAssertEqual(entries.item(titled: "Quit Barnata")?.action, .quit)
    }

    func testTheMenuOffersOneQuitAndNoAppLog() {
        let titles = MenuBuilder.entries(for: runningState()).allItems.map(\.title)
        XCTAssertEqual(titles.filter { $0.hasPrefix("Quit") }, ["Quit Barnata"])
        XCTAssertFalse(titles.contains("Open Barnata log"))
    }
}

final class SetupMenuTests: XCTestCase {
    private func setupItems(_ state: MenuState) -> [String] {
        MenuBuilder.entries(for: state).submenu(titled: "Setup")?.allItems.map(\.title) ?? []
    }

    func testApprovalItemIsShownUntilTheDaemonIsEnabled() {
        var unapproved = readyState()
        unapproved.daemonApproved = false
        XCTAssertTrue(setupItems(unapproved).contains("Approve background daemon…"))
        XCTAssertFalse(setupItems(readyState()).contains("Approve background daemon…"))
    }

    func testDriverItemsFollowTheDriverStatus() {
        let missing = readyState(status: daemonStatus(driver: driverStatus(installed: false, version: nil, activated: false)))
        XCTAssertTrue(setupItems(missing).contains("Install Karabiner driver…"))
        XCTAssertFalse(setupItems(missing).contains("Activate Karabiner driver…"))

        let inactive = readyState(status: daemonStatus(driver: driverStatus(activated: false)))
        XCTAssertTrue(setupItems(inactive).contains("Activate Karabiner driver…"))
        XCTAssertFalse(setupItems(inactive).contains("Install Karabiner driver…"))

        // Karabiner-Elements already owns a healthy driver, so neither item is offered
        let healthy = setupItems(readyState())
        XCTAssertFalse(healthy.contains("Install Karabiner driver…"))
        XCTAssertFalse(healthy.contains("Activate Karabiner driver…"))
    }

    func testNoDriverItemsBeforeTheDaemonHasReportedAnything() {
        var offline = readyState()
        offline.status = nil
        XCTAssertFalse(setupItems(offline).contains("Install Karabiner driver…"))
    }

    func testTheToggleItemsAreAlwaysPresent() {
        let items = setupItems(readyState())
        XCTAssertTrue(items.contains("Launch at login"))
        XCTAssertTrue(items.contains("Show in Dock"))
    }

    func testTheGrantItemAppearsOnlyWhileThePermissionIsMissing() {
        XCTAssertFalse(setupItems(readyState()).contains("Grant \(SystemPaneNames.accessibility)…"))

        var missing = readyState()
        missing.hasAccessibility = false
        XCTAssertTrue(setupItems(missing).contains("Grant \(SystemPaneNames.accessibility)…"))
    }

    func testInputMonitoringIsNotOffered() {
        var missing = readyState()
        missing.hasAccessibility = false
        XCTAssertFalse(setupItems(missing).contains { $0.localizedCaseInsensitiveContains("Input Monitoring") })
    }

    func testAFullyConfiguredSetupSubmenuIsJustTheTwoToggles() {
        XCTAssertEqual(setupItems(readyState()), ["Launch at login", "Show in Dock"])
    }

    func testTheTogglesCarryTheirCheckmarks() {
        var state = readyState()
        state.launchAtLogin = true
        state.showDockIcon = false
        let setup = MenuBuilder.entries(for: state).submenu(titled: "Setup")
        XCTAssertEqual(setup?.item(titled: "Launch at login")?.isChecked, true)
        XCTAssertEqual(setup?.item(titled: "Show in Dock")?.isChecked, false)
    }
}

final class VersionComparisonTests: XCTestCase {
    func testDottedVersionsCompareNumerically() {
        XCTAssertEqual(compareVersions("6.10.0", "6.9.0"), .orderedDescending)
        XCTAssertEqual(compareVersions("6.8.0", "6.8"), .orderedSame)
        XCTAssertEqual(compareVersions("6.8.0", "8.0.0"), .orderedAscending)
    }

    func testAnOlderInstalledDriverIsNotReportedAsNewer() {
        let older = readyState(status: daemonStatus(driver: driverStatus(version: "6.7.0", requiredVersion: "6.8.0")))
        XCTAssertNil(older.driverNewerThanRequired)
    }
}
