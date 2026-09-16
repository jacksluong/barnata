# 03. Implementation steps

Each phase ends with its acceptance criteria met before the next starts. Commit at the end of each phase. Everything below runs from `~/Developer/barnata`.

## Phase 0: prerequisites (manual, done by the user)

Done. Recorded in `Scripts/vars.sh`:

```sh
TEAM_ID=EE3526PL64
SIGNING_IDENTITY=E20ADF15A9A4E3839E3E0D9BC60B5DBE81BD2F8D   # expires 2031-09-05
```

`SIGNING_IDENTITY` always holds the SHA-1 hash, never the name.

`swift build` works on Command Line Tools alone, but `swift test` does not. `Scripts/vars.sh` exports `DEVELOPER_DIR` pointing at `/Applications/Xcode.app`. `xcodebuild` is never used.

## Phase 1: repo skeleton and core module

Done. `Package.swift` with targets `BarnataCore` (library), `Barnata` (executable), `barnata-daemon` (executable), `BarnataCoreTests`. Platforms `.macOS(.v14)`. Dependency: TOMLKit.

Remaining additions to `BarnataCore` in later phases: `ConfigWriter` (Phase 4), `ownerUID` on `DaemonStatus` (Phase 3).

## Phase 2: fetch kanata and the driver pkg

- `Scripts/fetch-kanata.sh`: downloads `macos-binaries-arm64.zip` for `KANATA_VERSION` from GitHub releases, verifies its sha256 against the value recorded in `Scripts/checksums.txt` (copied from the release's `sha256sums` asset), extracts `kanata_macos_arm64` (never `kanata_macos_cmd_allowed_arm64`) to `build/kanata`.
- Sanity check in the script: `build/kanata --version` prints the pinned version, and a temp config using `(cmd ...)` fails `--check` with `compiled to never allow cmd`.
- `Scripts/fetch-driver.sh`: downloads `Karabiner-DriverKit-VirtualHIDDevice-${DRIVER_VERSION}.pkg` from `DRIVER_PKG_URL`, verifies its sha256 against `Scripts/checksums.txt`, and `pkgutil --check-signature` must report team `G43BCU2T37`. Output: `build/driver.pkg`.
- Signing of `kanata` happens in `Scripts/sign.sh` with identifier `io.jackyluong.barnata.kanata`, hardened runtime.

Acceptance: `build/kanata` is `arm64` (`file build/kanata`) and passes both checks. `build/driver.pkg` passes the signature check.

## Phase 3: daemon

Targets: `BarnataDaemonKit` (library) and `BarnataDaemonKitTests`. `barnata-daemon/main.swift` only constructs and runs `XPCListener`.

- `XPCListener`: `NSXPCListener(machServiceName:)`, `setCodeSigningRequirement` on each incoming connection, idle-exit timer (60 s with no kanata child and no clients), `shutdown` handling.
- `Spawner` protocol with a `PosixSpawner` implementation (spawn, signal, wait, stdout/stderr capture, TCC responsibility disclaim).
- `ProcessSupervisor`: start, stop, restart, crash state from exit code, `BackoffPolicy`, stderr tail for `lastError`, log redirection with rotation.
- `SignatureCheck`: `SecStaticCodeCreateWithPath` + `SecRequirementCreateWithString` + `SecStaticCodeCheckValidity` helper used for kanata, the Karabiner daemon, and the Karabiner manager. `pkgutil --check-signature` wrapper for the pkg.
- `DriverManager`: `DriverStatus` collection, `ensureVirtualHIDDaemon`, `installDriver`, `activateDriver`.
- `RequestValidator`: enforces every rule in the privilege boundary section of `01-architecture.md`, including the uid ownership check.
- Logging through `os.Logger(subsystem: "io.jackyluong.barnata", category: "daemon")`.
- Daemon entitlements: none. Hardened runtime on.

Tests (XCTest, `BarnataDaemonKitTests`):

- `RequestValidator`: relative path, directory, symlink to directory, nonexistent file, file owned by another uid without world-read, port out of range, disallowed flag. Each rejected with a message naming the rule.
- `BackoffPolicy`: delays 1, 2, 4, 8, 30, 30; gives up on the sixth crash inside 2 minutes; counter resets after 2 minutes.
- `ProcessSupervisor` with a fake `Spawner`: exit 0 sets `idle`, exit 1 sets `crashed`, `autorestartOnCrash` schedules a restart, `stop` sends SIGTERM then SIGKILL after 3 s.

Manual test harness: `Scripts/build-app.sh --debug` produces a Developer ID signed bundle in `build/Barnata.app` without timestamp or notarization; `Scripts/dev-install.sh` copies it to `/Applications` and launches it.

Acceptance:

- `swift test` passes.
- `/Library/Logs/Barnata/kanata.log` contains kanata output and is readable by the user.

Three further checks need a daemon that launchd has actually started, which requires the `SMAppService` registration built in Phase 4. They are listed under Phase 4 acceptance:

- `launchctl print system/io.jackyluong.barnata.daemon` shows the service after approval.
- A throwaway Swift client connecting with the wrong signature is rejected.
- Start, stop, restart, and crash recovery (kill -9 the kanata pid) behave as specified.

## Phase 4: app

Targets: `BarnataAppKit` (library) and `BarnataAppKitTests`. `Barnata/main.swift` only creates `NSApplication` and `AppController`.

- `AppController`: startup sequence and update flow from `01-architecture.md`.
- `ConfigWatcher`: `DispatchSource` on the file and its directory, reload on change, echo suppression by modification date, rebuild menu.
- `ConfigWriter` in `BarnataCore`: line edit per `02-config-format.md`.
- `DaemonClient`: `NSXPCConnection(machServiceName:)`, reconnect with backoff, `subscribe` with an anonymous listener.
- `KanataTCPClient`: `NWConnection` to `127.0.0.1:<port>`, line framing, message enum, reconnect logic.
- `MenuState` and `MenuBuilder`: value type to `[MenuEntry]` tree, no AppKit imports.
- `StatusItemController`: renders `[MenuEntry]` into `NSMenu`, icon priority rules, template icon detection, 2 s reload flash, 400 ms delayed spinner for `starting` and `stopping`.
- `IconStore`: bundled status icons are SF Symbols (`keyboard`, `exclamationmark.triangle.fill`, `pause.circle`, `arrow.triangle.2.circlepath`), so no image assets are committed. `app.status_icons` still overrides them with PNGs from the config directory through `IconResolver`.
- `SetupActions`: `SMAppService.daemon` register and status, `SMAppService.mainApp` register/unregister, `SMAppService.openSystemSettingsLoginItems()`, URLs `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`, `?Privacy_Accessibility`, and the Driver Extensions pane, `NSWorkspace.activateFileViewerSelecting` on the app bundle. `IOHIDCheckAccess`/`IOHIDRequestAccess` and `AXIsProcessTrusted`/`AXIsProcessTrustedWithOptions` read and request the two privacy grants from the app, which is the only side that can show the prompt.
- `show_dock_icon`: `Info.plist` has `LSUIElement = true`; `true` in config calls `NSApp.setActivationPolicy(.regular)` at launch and on toggle.
- App entitlements: none. Hardened runtime on. No sandbox.

Tests (XCTest):

- `BarnataCoreTests`: `ConfigWriter` preserves comments, order, and trailing comments; inserts `[app]` when missing; appends a missing key; replaces an existing key.
- `BarnataAppKitTests`: `MenuBuilder` for each title line variant in `01-architecture.md`, the Setup items shown per `DriverStatus` and daemon status, "Running for another user" enables only Stop, preset checkmark, layer checkmark.

Acceptance:

Carried over from Phase 3, now that the app can register the daemon:

- `launchctl print system/io.jackyluong.barnata.daemon` shows the service after approval. `Scripts/dev-install.sh` prints it at the end of every install.
- A throwaway Swift client connecting with the wrong signature is rejected (build it with plain `swift build` so it is ad-hoc signed, connect to the Mach service, and confirm the daemon log shows the refusal).
- Start, stop, restart, and crash recovery behave as specified: `kill -9` the kanata pid with `autorestart_on_crash = true` and kanata is back within 2 s with `restartCount` incremented; with `false` the menu shows Crashed and the exit code.

Phase 4 proper:

- `swift test` passes.
- Fresh install flow on this machine: launch, approve daemon once with password, grant Input Monitoring and Accessibility to the bundled kanata, autorun preset starts, layer icon changes when switching layers on the keyboard.
- Quit the app; typing still remapped. Relaunch; menu shows Running and the current layer without restarting kanata.
- Edit `canary.kbd`, choose Reload config, `ConfigFileReload` arrives and the icon flashes.
- Set `show_dock_icon = true` in the file, the Dock icon appears within a second. Set it back, it disappears. Toggle it from the menu, the file changes and the watcher does not reload twice.
- Toggle Launch at login, the app appears under System Settings > Login Items.
- Break the config file syntax, menu shows the error, fix it, menu recovers.
- Install a build with a bumped `CFBundleVersion` over the running one with `dev-install.sh`; kanata restarts once and the menu shows the new version.

## Phase 5: packaging

- `Scripts/build-app.sh`: `swift build -c release` (`arm64`), assemble the bundle layout in `01-architecture.md`, write `Info.plist` with `CFBundleVersion` and `CFBundleShortVersionString` from `git describe`, copy `daemon.plist`, `kanata`, `driver.pkg`, resources. `--debug` builds debug and signs without `--timestamp`.
- `Scripts/sign.sh`: sign inside-out with `--options runtime` (`--timestamp` unless `--debug`): `kanata`, `barnata-daemon`, `Barnata` executable, then the bundle. Verify with `codesign --verify --deep --strict`.
- One-time before the first notarization: create an app-specific password at appleid.apple.com > Sign-In and Security > App-Specific Passwords, then `xcrun notarytool store-credentials barnata --apple-id <apple id> --team-id EE3526PL64` and paste it when prompted. The password is stored in the keychain under the profile name `barnata` and never appears in a script.
- `Scripts/notarize.sh`: `ditto -c -k --keepParent` to zip, `xcrun notarytool submit --keychain-profile barnata --wait`, `xcrun stapler staple`, re-zip.
- `Scripts/release.sh`: runs build, sign, notarize, tags, uploads `Barnata-<version>.zip` with `gh release create`, prints the sha256.

Acceptance: `spctl --assess --type execute --verbose build/Barnata.app` prints `accepted, source=Notarized Developer ID`. Copying the zip to a second Mac and opening it shows no Gatekeeper warning.

## Phase 6: distribution and dotfiles

Follow `04-distribution.md` and `05-dotfiles-migration.md`. Then run `06-verification.md` end to end on this machine after removing kanata-tray.

## Deferred

- Pre-login remapping (daemon starts the last preset at boot from a root-owned state file under `/Library/Application Support/Barnata/`).
- Hooks running in the app.
- Settings window.
- CI release workflow.
- Homebrew tap, once the repo is public.
- Multi-user support.
- Uninstall command (`Barnata.app/Contents/MacOS/Barnata --uninstall` that unregisters the daemon and login item and removes logs).
