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
        XCTAssertTrue(entries.labels.contains("Configs"))
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

final class PreferencesMenuTests: XCTestCase {
    func testSetupAndOpenConfigAreReplacedByOnePreferencesItem() {
        let entries = MenuBuilder.entries(for: readyState())
        XCTAssertNil(entries.submenu(titled: "Setup"))

        let titles = entries.allItems.map(\.title)
        XCTAssertFalse(titles.contains("Open config file"))
        XCTAssertEqual(titles.filter { $0 == "Preferences…" }.count, 1)
    }

    func testPreferencesOpensTheWindowAndKeepsItsShortcut() {
        let entries = MenuBuilder.entries(for: readyState())
        XCTAssertEqual(entries.item(titled: "Preferences…")?.action, .openPreferences)
        XCTAssertEqual(entries.item(titled: "Preferences…")?.keyEquivalent, ",")
        XCTAssertEqual(entries.item(titled: "Preferences…")?.isEnabled, true)
    }

    func testTheKanataLogItemSurvives() {
        XCTAssertEqual(MenuBuilder.entries(for: readyState()).item(titled: "Open kanata log")?.action, .openKanataLog)
    }

    func testTheSetupItemsAreGoneEvenWhileSetupIsIncomplete() {
        var incomplete = readyState(status: daemonStatus(driver: driverStatus(installed: false, version: nil)))
        incomplete.daemonApproved = false
        incomplete.hasAccessibility = false

        let titles = MenuBuilder.entries(for: incomplete).allItems.map(\.title)
        for gone in ["Approve background daemon…", "Install Karabiner driver…", "Launch at login", "Show in Dock"] {
            XCTAssertFalse(titles.contains(gone), gone)
        }
        // The title line is still how an unapproved daemon announces itself
        XCTAssertEqual(incomplete.title, "Daemon not approved")
    }

    func testPreferencesIsOfferedEvenWithABrokenConfig() {
        var broken = readyState()
        broken.configError = "unknown key"
        XCTAssertEqual(MenuBuilder.entries(for: broken).item(titled: "Preferences…")?.isEnabled, true)
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
