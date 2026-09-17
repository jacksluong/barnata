import AppKit
import BarnataCore
import Foundation

/// Removes everything Barnata installed: the launchd daemon, the login item, the config
/// folder, and the app bundle. Referenced kanata files are never touched.
@MainActor
public struct Uninstaller {
    public let setup: SetupActions
    public let configURL: URL

    public init(setup: SetupActions, configURL: URL) {
        self.setup = setup
        self.configURL = configURL
    }

    /// Calls back with a message when a step failed, otherwise quits the app
    public func run(completion: @escaping @MainActor (String?) -> Void) {
        setup.setLaunchAtLogin(false)
        setup.unregisterDaemon()

        let folder = configURL.deletingLastPathComponent()
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch {
            completion("Cannot delete \(folder.abbreviatedPath): \(error.localizedDescription)")
            return
        }

        guard let bundle = AppBundle.bundleURL else {
            log.notice("running outside an app bundle, nothing to move to the Trash")
            NSApp.terminate(nil)
            return
        }

        NSWorkspace.shared.recycle([bundle]) { _, error in
            MainActor.assumeIsolated {
                if let error {
                    completion("Cannot move Barnata to the Trash: \(error.localizedDescription)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

extension URL {
    /// `~/.config/barnata` rather than the full path, for text shown to the user
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
