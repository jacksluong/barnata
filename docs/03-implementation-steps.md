# 03. Implementation steps

Each phase ends with its acceptance criteria met before the next starts. Commit at the end of each phase. Everything below runs from `~/Developer/barnata`.

## Phase 0: prerequisites (manual, done by the user)

Only the signing certificate and the toolchain are needed before writing code. Notarization credentials belong to Phase 5.

1. Create a **Developer ID Application** certificate. Either in Xcode-beta > Settings > Accounts > Manage Certificates > `+` > Developer ID Application, or on developer.apple.com > Certificates with a CSR from Keychain Access. Confirm with `security find-identity -v -p codesigning`, which must list `Developer ID Application: <name> (<TEAMID>)`.
2. Take the certificate's SHA-1 hash from that same output. `SIGNING_IDENTITY` always holds the hash, never the name: `codesign -s "<name>"` fails as ambiguous when more than one Developer ID Application certificate is in the keychain.
3. Point the toolchain at Xcode-beta. `swift build` works on Command Line Tools alone, but `swift test` does not: Command Line Tools ships no `XCTest.framework` and cannot load the swift-testing macro plugin. Either `sudo xcode-select -s /Applications/Xcode-beta.app`, or rely on the `DEVELOPER_DIR` export in `Scripts/vars.sh`. `xcodebuild` is never used, and Command Line Tools already provides `notarytool` and `stapler`.

Values for this machine, recorded in `Scripts/vars.sh`:

```sh
TEAM_ID=EE3526PL64
SIGNING_IDENTITY=E20ADF15A9A4E3839E3E0D9BC60B5DBE81BD2F8D   # expires 2031-09-05
```

## Phase 1: repo skeleton and core module

- `git init`, `Package.swift` with targets `BarnataCore` (library), `Barnata` (executable), `barnata-daemon` (executable), `BarnataCoreTests`. Platforms `.macOS(.v14)`. Dependency: TOMLKit.
- `BarnataCore`: `Config` model and loader, `StartRequest`, `DaemonStatus`, `DriverStatus`, `CommandResult`, `KanataState`, `ArgAllowlist`, `IconResolver`, `XPCProtocols`, `Envelope` (Codable to `Data`).
- Tests: config example from `02-config-format.md` parses; unknown key fails; `extra_args = ["--danger"]` fails naming the flag; `~` expansion; array and string `kanata_config`; `layer_icons` override semantics; allowlist accepts `--emergency-exit-code 3` and rejects `--emergency-exit-code x`.

Acceptance: `swift build` and `swift test` pass.

## Phase 2: fetch and sign kanata

- `Scripts/fetch-kanata.sh`: downloads `kanata_macos_arm64` and `kanata_macos_x86_64` for `KANATA_VERSION` from GitHub releases (the plain assets, never `*_cmd_allowed*`), verifies sha256 against values recorded in `Scripts/kanata.sha256`, combines with `lipo -create` into `build/kanata`.
- Sanity check in the script: `build/kanata --version` prints the pinned version, and a temp config using `(cmd ...)` fails `--check` with `compiled to never allow cmd`.
- Signing of `kanata` happens in `Scripts/sign.sh` with identifier `io.jackyluong.barnata.kanata`, hardened runtime, timestamp.

Acceptance: `build/kanata` is universal (`lipo -info`) and passes both checks.

## Phase 3: daemon

- `main.swift`: `NSXPCListener(machServiceName:)`, set `setCodeSigningRequirement` on each incoming connection, idle-exit timer (60 s with no child and no clients).
- `ProcessSupervisor`: spawn, stop, restart, crash backoff, log redirection with rotation, TCC responsibility disclaim.
- `SignatureCheck`: `SecStaticCodeCreateWithPath` + `SecRequirementCreateWithString` + `SecStaticCodeCheckValidity` helper used for kanata, the Karabiner daemon, and the Karabiner manager.
- `DriverManager`: `DriverStatus` collection, `ensureVirtualHIDDaemon`, `activateDriver`.
- `RequestValidator`: enforces every rule in the privilege boundary section of `01-architecture.md`.
- Logging through `os.Logger(subsystem: "io.jackyluong.barnata", category: "daemon")`.
- Daemon entitlements: none. Hardened runtime on.

Manual test harness for this phase: `Scripts/build-app.sh --debug` produces an unsigned-for-distribution but ad-hoc-signed bundle in `build/Barnata.app`; `Scripts/dev-install.sh` copies it to `/Applications` and launches it. This phase uses the Developer ID identity from Phase 0.

Acceptance:

- `launchctl print system/io.jackyluong.barnata.daemon` shows the service after approval.
- A throwaway Swift client connecting with the wrong signature is rejected (test by running the client ad-hoc signed).
- Start, stop, restart, and crash recovery (kill -9 the kanata pid) behave as specified.
- `/Library/Logs/Barnata/kanata.log` contains kanata output and is readable by the user.

## Phase 4: app

- `AppDelegate`: startup sequence from `01-architecture.md`, config file watcher (`DispatchSource` on the file and its directory, reload on change, rebuild menu).
- `DaemonClient`: `NSXPCConnection(machServiceName:)`, reconnect with backoff, `subscribe` with an anonymous listener.
- `KanataTCPClient`: `NWConnection` to `127.0.0.1:<port>`, line framing, message enum, reconnect logic.
- `StatusItemController` and `MenuBuilder`: menu from `01-architecture.md`, icon priority rules, template icon detection, 2 s reload flash.
- `SetupActions`: `SMAppService.daemon` register and status, `SMAppService.mainApp` register/unregister, `SMAppService.openSystemSettingsLoginItems()`, URLs `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` and `?Privacy_Accessibility`, `NSWorkspace.activateFileViewerSelecting` on the bundled kanata, driver pkg URL.
- `show_dock_icon`: `Info.plist` has `LSUIElement = true`; `true` in config calls `NSApp.setActivationPolicy(.regular)` at launch and on toggle. Toggle writes the key back to `config.toml` preserving the rest of the file (TOMLKit round trip on the `[app]` table only).
- App entitlements: none. Hardened runtime on. No sandbox.

Acceptance:

- Fresh install flow on this machine: launch, approve daemon once with password, grant Input Monitoring and Accessibility to the bundled kanata, autorun preset starts, layer icon changes when switching layers on the keyboard.
- Quit the app; typing still remapped. Relaunch; menu shows Running and the current layer without restarting kanata.
- Edit `canary.kbd`, choose Reload config, `ConfigFileReload` arrives and the icon flashes.
- Set `show_dock_icon = true` in the file, the Dock icon appears within a second. Set it back, it disappears.
- Toggle Launch at login, the app appears under System Settings > Login Items.
- Break the config file syntax, menu shows the error, fix it, menu recovers.

## Phase 5: packaging

- `Scripts/build-app.sh`: `swift build -c release --arch arm64 --arch x86_64`, assemble the bundle layout in `01-architecture.md`, write `Info.plist` with `CFBundleVersion` and `CFBundleShortVersionString` from `git describe`, copy `daemon.plist`, `kanata`, resources.
- `Scripts/sign.sh`: sign inside-out with `--options runtime --timestamp`: `kanata`, `barnata-daemon`, `Barnata` executable, then the bundle. Verify with `codesign --verify --deep --strict` and `spctl --assess --type execute`.
- One-time before the first notarization: create an app-specific password at appleid.apple.com > Sign-In and Security > App-Specific Passwords, then `xcrun notarytool store-credentials barnata --apple-id <apple id> --team-id EE3526PL64` and paste it when prompted. The password is stored in the keychain under the profile name `barnata` and never appears in a script.
- `Scripts/notarize.sh`: `ditto -c -k --keepParent` to zip, `xcrun notarytool submit --keychain-profile barnata --wait`, `xcrun stapler staple`, re-zip.
- `Scripts/release.sh`: runs the three above, tags, uploads `Barnata-<version>.zip` with `gh release create`, prints the sha256 for the cask.

Acceptance: `spctl --assess --type execute --verbose build/Barnata.app` prints `accepted, source=Notarized Developer ID`. Copying the zip to a second Mac and opening it shows no Gatekeeper warning.

## Phase 6: distribution and dotfiles

Follow `04-distribution.md` and `05-dotfiles-migration.md`. Then run `06-verification.md` end to end on this machine after removing kanata-tray.

## Deferred

- Pre-login remapping (daemon starts the last preset at boot from a root-owned state file).
- Hooks running in the app.
- Settings window.
- CI release workflow.
- Uninstall command (`Barnata.app/Contents/MacOS/Barnata --uninstall` that unregisters the daemon and login item and removes `/Library/Application Support/Barnata` and logs).
