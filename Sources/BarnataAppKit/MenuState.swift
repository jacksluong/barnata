import BarnataCore
import Foundation

/// System Settings pane names, which Apple has changed across releases
public enum SystemPaneNames {
    /// macOS 27 renamed the Accessibility pane to Device Control and Data Access
    public static var accessibility: String {
        let macOS27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(macOS27)
            ? "Device Control and Data Access"
            : "Accessibility"
    }
}

/// What the status item shows in place of an icon
public enum StatusPresentation: Sendable, Equatable {
    case status(IconResolver.StatusIcon)
    case layer(String)
}

/// Everything the menu needs, as one value. No AppKit, so `MenuBuilder` stays testable.
public struct MenuState: Sendable, Equatable {
    public var appVersion: String
    public var daemonApproved: Bool
    public var hasAccessibility: Bool
    public var configPath: String
    public var configError: String?
    public var presetNames: [String]
    public var status: DaemonStatus?
    public var currentUID: uid_t
    public var layers: [String]
    public var currentLayer: String?
    public var isReloading: Bool
    public var lastReloadError: String?
    public var lastActionError: String?
    public var launchAtLogin: Bool
    public var showDockIcon: Bool

    public init(
        appVersion: String = "0",
        daemonApproved: Bool = false,
        hasAccessibility: Bool = true,
        configPath: String = "",
        configError: String? = nil,
        presetNames: [String] = [],
        status: DaemonStatus? = nil,
        currentUID: uid_t = 0,
        layers: [String] = [],
        currentLayer: String? = nil,
        isReloading: Bool = false,
        lastReloadError: String? = nil,
        lastActionError: String? = nil,
        launchAtLogin: Bool = false,
        showDockIcon: Bool = false
    ) {
        self.appVersion = appVersion
        self.daemonApproved = daemonApproved
        self.hasAccessibility = hasAccessibility
        self.configPath = configPath
        self.configError = configError
        self.presetNames = presetNames
        self.status = status
        self.currentUID = currentUID
        self.layers = layers
        self.currentLayer = currentLayer
        self.isReloading = isReloading
        self.lastReloadError = lastReloadError
        self.lastActionError = lastActionError
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
    }

    // MARK: - Derived facts

    public var state: KanataState { status?.state ?? .idle }

    public var driver: DriverStatus? { status?.driver }

    public var isRunning: Bool { state == .running }

    public var activePresetName: String? {
        guard state == .running || state == .starting else { return nil }
        return status?.presetName
    }

    /// The daemon is running kanata for a different login account
    public var isRunningForAnotherUser: Bool {
        guard let owner = status?.ownerUID, state != .idle else { return false }
        return owner != currentUID
    }

    /// Installed driver version and the version this build needs, when the installed one is newer
    public var driverNewerThanRequired: (installed: String, required: String)? {
        guard let driver, let installed = driver.version, driver.installed else { return nil }
        guard compareVersions(installed, driver.requiredVersion) == .orderedDescending else { return nil }
        return (installed, driver.requiredVersion)
    }

    /// The grant kanata cannot start without, named as System Settings names it
    public var missingPermission: String? {
        hasAccessibility ? nil : SystemPaneNames.accessibility
    }

    /// Kanata control items are dead while the daemon is unapproved or another user owns the process
    public var canControlKanata: Bool { daemonApproved && !isRunningForAnotherUser }

    public var title: String {
        if !daemonApproved { return "Daemon not approved" }
        if let configError { return "Config error: \(configError)" }
        if let newer = driverNewerThanRequired {
            return "Driver \(newer.installed) is newer than required \(newer.required)"
        }
        if let driver, !driver.installed { return "Driver not installed" }
        if isRunningForAnotherUser { return "Running for another user" }
        // A missing grant is why kanata keeps exiting, so say that instead of the exit code
        if let missingPermission, state == .idle || state == .crashed {
            return "\(missingPermission) not granted"
        }

        switch state {
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        case .crashed: return "Crashed (exit \(status?.lastExitCode ?? 0))"
        case .idle: return "Not running"
        case .running:
            let file = (status?.configPath as NSString?)?.lastPathComponent ?? "kanata"
            guard let currentLayer else { return "Running (\(file))" }
            return "Running (\(file), layer: \(currentLayer))"
        }
    }

    /// Extra disabled lines under the title, for errors too long to fit in it
    public var detailLines: [String] {
        var lines: [String] = []
        if state == .crashed, let error = status?.lastError, let first = firstLine(of: error) {
            lines.append(first)
        }
        if let lastReloadError, let first = firstLine(of: lastReloadError) {
            lines.append("Reload failed: \(first)")
        }
        if let lastActionError, let first = firstLine(of: lastActionError) {
            lines.append(first)
        }
        return lines
    }

    /// Priority order from 01-architecture.md
    public var presentation: StatusPresentation {
        if !daemonApproved { return .status(.crashed) }
        if configError != nil { return .status(.crashed) }
        if let driver, !driver.installed { return .status(.crashed) }
        if missingPermission != nil, state != .running { return .status(.crashed) }
        if state == .crashed { return .status(.crashed) }
        if state == .idle { return .status(.paused) }
        if isReloading { return .status(.reloading) }
        if state == .running, let currentLayer { return .layer(currentLayer) }
        return .status(.normal)
    }

    /// The status item swaps in a spinner when one of these lasts longer than 400 ms
    public var isTransitioning: Bool { state == .starting || state == .stopping }
}

private func firstLine(of text: String) -> String? {
    text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        .flatMap { $0.isEmpty ? nil : $0 }
}

/// Numeric dotted comparison, so 6.10.0 sorts above 6.9.0
func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    for index in 0..<Swift.max(left.count, right.count) {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b { return a < b ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}
