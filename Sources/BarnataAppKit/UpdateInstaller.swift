import AppKit
import Darwin
import Foundation

/// Runs `brew upgrade --cask` for the app itself.
///
/// Homebrew walks the process tree of its own `brew` process and refuses to quit an app it is
/// running inside, so the shell is orphaned to launchd before Homebrew starts. Barnata then quits
/// itself, which stops the daemon the clean way, and the shell opens the new bundle afterwards.
public enum UpdateInstaller {
    public static let caskToken = "jacksluong/tap/barnata"
    public static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    /// Tenths of a second the shell waits for Barnata to go before upgrading anyway
    public static let quitWait = 150

    public static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Barnata/update.log")
    }

    /// Where the shell leaves Homebrew's exit code, since Barnata is not running to see it
    public static var statusURL: URL {
        logURL.deletingLastPathComponent().appending(path: "update-status")
    }

    public static var brewURL: URL? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Starts the upgrade, returning a message when it could not be started at all.
    /// The caller quits the app once this returns nil.
    @MainActor
    public static func start(appBundle: URL) -> String? {
        guard let brew = brewURL else {
            return "Homebrew is not installed, so Barnata cannot update itself."
        }
        try? FileManager.default.removeItem(at: statusURL)

        do {
            try spawn(script: script(brew: brew.path, appBundle: appBundle), brewPrefix: brew.deletingLastPathComponent())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Homebrew's exit code from the last run, read once and cleared
    public static func takeResult() -> Int32? {
        guard let text = try? String(contentsOf: statusURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: statusURL)
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    /// The whole run sits in a backgrounded brace group, so `sh` exits at once and leaves
    /// Homebrew parented to launchd with no app above it
    static func script(brew: String, appBundle: URL) -> String {
        """
        {
          waited=0
          while /bin/kill -0 \(getpid()) 2>/dev/null && [ "$waited" -lt \(quitWait) ]; do
            /bin/sleep 0.1
            waited=$((waited + 1))
          done
          echo "=== $(date '+%Y-%m-%d %H:%M:%S') barnata update"
          "\(brew)" upgrade --cask \(caskToken)
          status=$?
          echo "=== brew exited $status"
          echo "$status" > "\(statusURL.path)"
          /usr/bin/open -a "\(appBundle.path)"
        } &
        """
    }

    private static func environment(brewPrefix: URL) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        return [
            "PATH": [brewPrefix.path, "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":"),
            "HOME": inherited["HOME"] ?? NSHomeDirectory(),
            "USER": inherited["USER"] ?? NSUserName(),
            "LOGNAME": inherited["LOGNAME"] ?? NSUserName(),
            "SHELL": "/bin/sh",
            // Nothing can answer a prompt here, so Homebrew should fail rather than wait for one
            "NONINTERACTIVE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
        ]
    }

    /// posix_spawn with output appended to the log file, in a session of its own so that launchd
    /// tearing down Barnata's process group leaves Homebrew running
    private static func spawn(script: String, brewPrefix: URL) throws {
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
        let variables = environment(brewPrefix: brewPrefix).map { "\($0.key)=\($0.value)" }
        let status = withCStringArray(argv) { arguments in
            withCStringArray(variables) { environment in
                posix_spawn(&pid, "/bin/sh", &fileActions, &attributes, arguments, environment)
            }
        }

        guard status == 0 else {
            throw UpdateError(description: "cannot start Homebrew: \(String(cString: strerror(status)))")
        }
    }
}

struct UpdateError: LocalizedError {
    let description: String

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
