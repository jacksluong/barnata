import AppKit
import BarnataCore
import Foundation

/// Removes everything Barnata installed: the launchd daemon, the login item, the config
/// folder, and the app bundle. Referenced kanata files are never touched.
@MainActor
public struct Uninstaller {
    /// Homebrew's whole record of a cask install, owned by the user who installed it
    nonisolated static let caskroomFolders = [
        URL(fileURLWithPath: "/opt/homebrew/Caskroom/barnata"),
        URL(fileURLWithPath: "/usr/local/Caskroom/barnata"),
    ]

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

        Uninstaller.removeCaskroomRecords()

        guard let bundle = AppBundle.bundleURL else {
            log.notice("running outside an app bundle, nothing to move to the Trash")
            terminateApp()
            return
        }

        NSWorkspace.shared.recycle([bundle]) { _, error in
            MainActor.assumeIsolated {
                if let error {
                    completion("Cannot move Barnata to the Trash: \(error.localizedDescription)")
                } else {
                    terminateApp()
                }
            }
        }
    }

    /// Deletes a Homebrew install's Caskroom folder so `brew` stops listing Barnata. A failure is
    /// only logged, since the app itself still uninstalls. Returns the folders that could not be deleted.
    @discardableResult
    nonisolated static func removeCaskroomRecords(_ folders: [URL] = caskroomFolders) -> [URL] {
        folders.filter { folder in
            guard FileManager.default.fileExists(atPath: folder.path) else { return false }
            do {
                try FileManager.default.removeItem(at: folder)
                return false
            } catch {
                log.error("cannot delete \(folder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
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
