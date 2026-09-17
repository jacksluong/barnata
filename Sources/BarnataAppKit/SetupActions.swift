import AppKit
import ApplicationServices
import BarnataCore
import Foundation
import ServiceManagement

/// Every jump into System Settings and every SMAppService call the Setup menu makes
@MainActor
public struct SetupActions {
    public static let daemonPlistName = "\(barnataDaemonIdentifier).plist"

    private static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let driverExtensionsURL = URL(
        string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.driver_extension")!

    private let daemon = SMAppService.daemon(plistName: SetupActions.daemonPlistName)

    public init() {}

    // MARK: - Daemon registration

    public var daemonStatus: SMAppService.Status { daemon.status }

    public var isDaemonApproved: Bool { daemon.status == .enabled }

    /// Registering an already-registered daemon throws, which is not an error worth surfacing
    public func registerDaemon() {
        guard daemon.status != .enabled else { return }
        do {
            try daemon.register()
            log.notice("registered the daemon, status is now \(String(describing: self.daemon.status), privacy: .public)")
        } catch {
            log.error("cannot register the daemon: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Unregistering also stops whatever the daemon is running, so uninstall needs nothing else
    public func unregisterDaemon() {
        do {
            try daemon.unregister()
            log.notice("unregistered the daemon")
        } catch {
            log.error("cannot unregister the daemon: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Login item

    public var isLaunchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("cannot set launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Privacy permissions

    /// tccd resolves kanata's request to the enclosing app bundle, so one grant covers both
    public var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and registers Barnata in the pane.
    /// kanata cannot do this itself: tccd refuses to draw UI for a uid 0 requester.
    @discardableResult
    public func requestAccessibility() -> Bool {
        // The imported kAXTrustedCheckOptionPrompt global is not Sendable; its value is this string
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibility() {
        revealAppInFinder()
        NSWorkspace.shared.open(SetupActions.accessibilityURL)
    }

    public func openDriverExtensions() {
        NSWorkspace.shared.open(SetupActions.driverExtensionsURL)
    }

    /// The privacy panes list the app bundle, not the kanata binary, so reveal the bundle
    public func revealAppInFinder() {
        guard let bundle = AppBundle.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([bundle])
    }

    // MARK: - Files

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Paths inside the app's own bundle, the app-side twin of the daemon's BundleLayout
public enum AppBundle {
    public static let kanataLogURL = URL(fileURLWithPath: "/Library/Logs/Barnata/kanata.log")

    public static var macOSDirectory: URL {
        Bundle.main.executableURL?.deletingLastPathComponent().standardizedFileURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
    }

    public static var kanataURL: URL { macOSDirectory.appending(path: "kanata") }

    /// The .app itself, nil when running as a bare executable outside a bundle
    public static var bundleURL: URL? {
        let candidate = macOSDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return candidate.pathExtension == "app" ? candidate : nil
    }

    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    public static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `kanata --version` from the bundled binary, so the app can spot a stale running copy
    public static func kanataVersion() -> String? {
        let executable = kanataURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        guard (try? process.run()) != nil else { return nil }
        let output = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
