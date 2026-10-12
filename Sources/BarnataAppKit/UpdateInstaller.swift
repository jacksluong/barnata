import AppKit
import BarnataCore
import CryptoKit
import Darwin
import Foundation

/// Downloads a release DMG, checks it, and swaps the new app in for the running one.
///
/// Every check runs while Barnata is still up, so a bad download changes nothing. A file that
/// `URLSession` downloads carries no quarantine flag, so the installed app never goes through
/// Gatekeeper's first-launch check. The detached shell only waits for Barnata to quit, swaps the
/// bundles, and opens the new one.
public enum UpdateInstaller {
    public static let installedBundle = URL(fileURLWithPath: "/Applications/Barnata.app")
    /// Tenths of a second the shell waits for Barnata to go before swapping anyway
    public static let quitWait = 150
    static let moveToApplicationsMessage = "Move Barnata to Applications, then try again."

    public static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Barnata/update.log")
    }

    /// Where the shell leaves the swap's exit code, since Barnata is not running to see it
    public static var statusURL: URL {
        logURL.deletingLastPathComponent().appending(path: "update-status")
    }

    /// True only for `/Applications/Barnata.app` itself, never a translocated copy of it
    static func isInstallable(bundle: URL) -> Bool {
        let path = bundle.standardizedFileURL.path
        return path == installedBundle.path && !path.contains("/AppTranslocation/")
    }

    /// `/Applications` and the bundle both need to be writable to rename the bundle aside
    static func canReplace(bundle: URL) -> Bool {
        let fileManager = FileManager.default
        let folder = bundle.deletingLastPathComponent().path
        guard fileManager.isWritableFile(atPath: folder) else { return false }
        return !fileManager.fileExists(atPath: bundle.path) || fileManager.isWritableFile(atPath: bundle.path)
    }

    /// Downloads, hashes, unpacks, and checks `update`, returning the staged app ready for `start`
    @concurrent
    public static func prepare(_ update: AvailableUpdate, appBundle: URL) async throws -> URL {
        guard isInstallable(bundle: appBundle), canReplace(bundle: appBundle) else {
            throw UpdateError(moveToApplicationsMessage)
        }
        guard let downloadURL = update.downloadURL, let expectedHash = update.sha256 else {
            throw UpdateError("Barnata v\(update.version) has no installer.")
        }

        let staging = try makeStagingFolder(for: appBundle)
        do {
            let dmg = staging.appending(path: downloadURL.lastPathComponent)
            try await download(downloadURL, to: dmg)

            let actualHash = try sha256Hex(of: dmg)
            guard actualHash == expectedHash else {
                throw UpdateError("The download does not match the release (sha256 \(actualHash), expected \(expectedHash)).")
            }

            let staged = staging.appending(path: installedBundle.lastPathComponent)
            try unpack(dmg, into: staged, mountPoint: staging.appending(path: "mount"))
            try? FileManager.default.removeItem(at: dmg)

            try verify(staged: staged, expectedVersion: update.version)
            return staged
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The signature, Gatekeeper, bundle id, and version checks every staged app goes through,
    /// followed by clearing any quarantine flag
    public static func verify(staged: URL, expectedVersion: String?) throws {
        guard let teamID = CodeSignature.selfTeamIdentifier() else {
            throw UpdateError("Barnata is not signed, so it cannot check the new version.")
        }
        do {
            try CodeSignature.validate(
                path: staged.path,
                requirement: "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\"",
                flags: SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
            )
        } catch {
            throw UpdateError("The new version is not signed by the Barnata developer (\(error)).")
        }

        let assessment = Command.run("/usr/sbin/spctl", ["--assess", "--type", "execute", staged.path])
        guard assessment.exitCode == 0 else {
            throw UpdateError("Gatekeeper rejected the new version: \(assessment.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let info = NSDictionary(contentsOf: staged.appending(path: "Contents/Info.plist")) as? [String: Any] ?? [:]
        let identifier = info["CFBundleIdentifier"] as? String
        guard identifier != nil, identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("The new version has the bundle identifier \(identifier ?? "none"), expected \(Bundle.main.bundleIdentifier ?? "none").")
        }
        if let expectedVersion {
            let version = info["CFBundleShortVersionString"] as? String
            guard version == expectedVersion else {
                throw UpdateError("The download is version \(version ?? "unknown"), expected \(expectedVersion).")
            }
        }

        removeQuarantine(from: staged)
    }

    /// Starts the swap, then the caller quits the app. `staged` sits in its own staging folder,
    /// which the shell deletes once it is done.
    public static func start(staged: URL, appBundle: URL) throws {
        try? FileManager.default.removeItem(at: statusURL)
        try spawn(script: script(
            pid: getpid(),
            staged: staged,
            appBundle: appBundle,
            staging: staged.deletingLastPathComponent()
        ))
    }

    /// The swap's exit code from the last run, read once and cleared
    public static func takeResult() -> Int32? {
        guard let text = try? String(contentsOf: statusURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: statusURL)
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @MainActor
    public static func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    /// A folder on the same volume as `bundle`, so moving the staged app into place is a rename
    static func makeStagingFolder(for bundle: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: bundle.deletingLastPathComponent(),
            create: true
        )
    }

    /// Streams the file through SHA256 so a large DMG is never held in memory whole
    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The whole run sits in a backgrounded brace group, so `sh` exits at once and the swap
    /// outlives Barnata. A failed move puts the old app back before anything is opened.
    static func script(pid: pid_t, staged: URL, appBundle: URL, staging: URL) -> String {
        let app = quoted(appBundle.path)
        let new = quoted(staged.path)
        let old = quoted(staging.appending(path: "Barnata-old.app").path)
        return """
        {
          waited=0
          while /bin/kill -0 \(pid) 2>/dev/null && [ "$waited" -lt \(quitWait) ]; do
            /bin/sleep 0.1
            waited=$((waited + 1))
          done
          echo "=== $(date '+%Y-%m-%d %H:%M:%S') barnata update"
          status=0
          if [ -e \(app) ]; then
            /bin/mv \(app) \(old) || status=2
          fi
          if [ "$status" -eq 0 ] && ! /bin/mv \(new) \(app); then
            status=3
            if [ -e \(old) ]; then
              /bin/mv \(old) \(app) || status=4
            fi
          fi
          echo "=== swap exited $status"
          echo "$status" > \(quoted(statusURL.path))
          /usr/bin/open \(app)
          /bin/rm -rf \(quoted(staging.path))
        } &
        """
    }

    /// Single quotes for `sh`, with any single quote inside closed, escaped, and reopened
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError("The download failed with HTTP \(http.statusCode).")
        }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    /// Mounts the DMG out of sight, copies the app out, and always detaches
    private static func unpack(_ dmg: URL, into staged: URL, mountPoint: URL) throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = Command.run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path,
        ])
        guard attach.exitCode == 0 else {
            throw UpdateError("Cannot open the download: \(attach.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        defer {
            if Command.run("/usr/bin/hdiutil", ["detach", mountPoint.path]).exitCode != 0 {
                _ = Command.run("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path])
            }
        }

        let source = mountPoint.appending(path: installedBundle.lastPathComponent)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError("The download has no \(installedBundle.lastPathComponent) inside.")
        }
        let copy = Command.run("/usr/bin/ditto", [source.path, staged.path])
        guard copy.exitCode == 0 else {
            throw UpdateError("Cannot copy the new version: \(copy.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func removeQuarantine(from bundle: URL) {
        var paths = [bundle.path]
        if let enumerator = FileManager.default.enumerator(atPath: bundle.path) {
            for case let relative as String in enumerator {
                paths.append(bundle.appending(path: relative).path)
            }
        }
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    private static func environment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        return [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": inherited["HOME"] ?? NSHomeDirectory(),
            "USER": inherited["USER"] ?? NSUserName(),
            "LOGNAME": inherited["LOGNAME"] ?? NSUserName(),
            "SHELL": "/bin/sh",
        ]
    }

    /// posix_spawn with output appended to the log file, in a session of its own so that launchd
    /// tearing down Barnata's process group leaves the swap running
    private static func spawn(script: String) throws {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(
            &fileActions, STDOUT_FILENO, logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&fileActions, STDOUT_FILENO, STDERR_FILENO)

        var pid: pid_t = 0
        let argv = ["/bin/sh", "-c", script]
        let variables = environment().map { "\($0.key)=\($0.value)" }
        let status = withCStringArray(argv) { arguments in
            withCStringArray(variables) { environment in
                posix_spawn(&pid, "/bin/sh", &fileActions, &attributes, arguments, environment)
            }
        }

        guard status == 0 else {
            throw UpdateError("Cannot start the update: \(String(cString: strerror(status)))")
        }
    }
}

struct UpdateError: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? { description }
}

/// Builds the NULL-terminated char* array posix_spawn wants, valid only inside `body`
private func withCStringArray<R>(
    _ values: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R
) -> R {
    let pointers: [UnsafeMutablePointer<CChar>?] = values.map { strdup($0) } + [nil]
    defer { pointers.forEach { free($0) } }
    var mutable = pointers
    return body(&mutable)
}
