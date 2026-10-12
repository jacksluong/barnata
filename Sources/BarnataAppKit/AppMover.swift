import AppKit
import BarnataCore
import Foundation

/// Moves a copy running from a DMG, Downloads, or anywhere else into `/Applications`, where the
/// daemon registration and the updater expect it.
@MainActor
public enum AppMover {
    public enum Choice {
        case move
        case notNow
    }

    /// The original bundle to move to the Trash once the swap succeeds and the moved copy launches
    static let originalPathKey = "movedFromPath"

    /// True anywhere but `/Applications/Barnata.app`, including a translocated copy, which is
    /// macOS running a quarantined app from a hidden read-only folder
    nonisolated static func needsMove(bundle: URL) -> Bool {
        !UpdateInstaller.isInstallable(bundle: bundle)
    }

    public static func ask() -> Choice {
        let alert = NSAlert()
        alert.messageText = "Move Barnata to Applications?"
        alert.informativeText = "Barnata needs to be in the Applications folder to start at login and update itself."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .move : .notNow
    }

    public static func reportFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Barnata could not be moved"
        alert.informativeText = UpdateInstaller.moveToApplicationsMessage
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Copies and checks the running bundle, then starts the swap. The caller quits once this returns.
    public static func move(bundle: URL) async throws {
        let staged = try await stage(bundle: bundle)
        try UpdateInstaller.start(staged: staged, appBundle: UpdateInstaller.installedBundle)
        UserDefaults.standard.set(trashablePath(of: bundle), forKey: originalPathKey)
    }

    /// Runs on the moved copy's first launch. The original goes to the Trash only when the swap
    /// reported success, so a failed move never loses the only copy.
    public static func finishMove(swapSucceeded: Bool, runningBundle: URL) {
        guard let path = UserDefaults.standard.string(forKey: originalPathKey) else { return }
        UserDefaults.standard.removeObject(forKey: originalPathKey)
        guard swapSucceeded, !needsMove(bundle: runningBundle) else { return }

        let original = URL(fileURLWithPath: path)
        guard original.standardizedFileURL != runningBundle.standardizedFileURL,
              FileManager.default.fileExists(atPath: original.path)
        else { return }

        NSWorkspace.shared.recycle([original]) { _, error in
            if let error {
                log.error("cannot move the original copy to the Trash: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @concurrent
    private static func stage(bundle: URL) async throws -> URL {
        let installed = UpdateInstaller.installedBundle
        guard UpdateInstaller.canReplace(bundle: installed) else {
            throw UpdateError(UpdateInstaller.moveToApplicationsMessage)
        }

        let staging = try UpdateInstaller.makeStagingFolder(for: installed)
        let staged = staging.appending(path: installed.lastPathComponent)
        do {
            let copy = Command.run("/usr/bin/ditto", [bundle.path, staged.path])
            guard copy.exitCode == 0 else {
                throw UpdateError("Cannot copy Barnata: \(copy.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            try UpdateInstaller.verify(staged: staged, expectedVersion: nil)
            return staged
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The original's path when it can go to the Trash, nil when it is a translocated copy whose
    /// real location is unknown or sits on a read-only volume such as the DMG
    private static func trashablePath(of bundle: URL) -> String? {
        let path = bundle.standardizedFileURL.path
        guard !path.contains("/AppTranslocation/") else { return nil }
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
        guard !readOnly, FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            return nil
        }
        return path
    }
}
