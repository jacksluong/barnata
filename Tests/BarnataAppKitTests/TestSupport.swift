import BarnataCore
import Foundation

@testable import BarnataAppKit

let testUID: uid_t = 501
let otherUID: uid_t = 502

func driverStatus(
    installed: Bool = true,
    version: String? = "6.8.0",
    requiredVersion: String = "6.8.0",
    activated: Bool = true
) -> DriverStatus {
    DriverStatus(
        installed: installed,
        version: version,
        requiredVersion: requiredVersion,
        activated: activated,
        vhidDaemonRunning: installed,
        vhidDaemonManagedByBarnata: false
    )
}

func daemonStatus(
    state: KanataState = .idle,
    presetName: String? = nil,
    configPath: String? = nil,
    tcpPort: Int? = nil,
    ownerUID: uid_t? = nil,
    lastExitCode: Int32? = nil,
    lastError: String? = nil,
    driver: DriverStatus = driverStatus()
) -> DaemonStatus {
    DaemonStatus(
        daemonVersion: "7",
        kanataVersion: "kanata 1.12.0",
        state: state,
        pid: state == .running ? 4242 : nil,
        presetName: presetName,
        configPath: configPath,
        tcpPort: tcpPort,
        ownerUID: ownerUID,
        lastExitCode: lastExitCode,
        lastError: lastError,
        restartCount: 0,
        driver: driver
    )
}

/// A state with the daemon approved, the driver healthy, and two presets
func readyState(
    status: DaemonStatus? = daemonStatus(),
    layers: [String] = [],
    currentLayer: String? = nil
) -> MenuState {
    MenuState(
        appVersion: "7",
        daemonApproved: true,
        configPath: "/Users/test/.config/barnata/config.toml",
        presetNames: ["Default", "Other"],
        status: status,
        currentUID: testUID,
        layers: layers,
        currentLayer: currentLayer
    )
}

/// The running state used by most menu assertions
func runningState(layer: String? = "base") -> MenuState {
    readyState(
        status: daemonStatus(
            state: .running,
            presetName: "Default",
            configPath: "/Users/test/.config/kanata/example.kbd",
            tcpPort: 5829,
            ownerUID: testUID
        ),
        layers: ["base", "typing", "arrows"],
        currentLayer: layer
    )
}

extension Array where Element == MenuEntry {
    var enabledActions: [MenuAction] {
        allItems.filter { $0.isEnabled && $0.action != .none }.map(\.action)
    }

    var labels: [String] {
        compactMap { if case .label(let text) = $0 { return text } else { return nil } }
    }
}
