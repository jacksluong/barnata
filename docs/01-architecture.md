# 01. Architecture

## Components

```
Barnata.app/
  Contents/
    Info.plist                       LSUIElement = true
    MacOS/
      Barnata                      menu bar app, runs as the user
      barnata-daemon               root daemon, registered via SMAppService
      kanata                         upstream arm64 release binary, re-signed
    Library/LaunchDaemons/
      io.jackyluong.barnata.daemon.plist
    Resources/
      status-icons/                  optional PNG overrides for default, crashed, paused, reloading
      Karabiner-DriverKit-VirtualHIDDevice-<DRIVER_VERSION>.pkg
      driver-requirements.json       required driver pkg version and pkg file name
```

Three processes:

| Process | User | Lifetime | Job |
|---|---|---|---|
| `Barnata` | you | while the menu bar item is shown | menu, icons, config file, TCP client to kanata, XPC client to daemon |
| `barnata-daemon` | root | launched on demand by launchd, exits when idle | spawns and supervises kanata and, when needed, the Karabiner virtual HID daemon; installs the driver pkg |
| `kanata` | root | child of the daemon | key remapping, TCP server on localhost |

## Privilege boundary

The daemon is the only code that runs as root and is written by this project. Rules it enforces on every request:

- The kanata executable is always `<own bundle>/Contents/MacOS/kanata`. The path is derived from the daemon's own executable path, never from the request.
- Before every spawn, the daemon validates the kanata binary with `SecStaticCodeCheckValidity` against the designated requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>" and identifier "io.jackyluong.barnata.kanata"`. A failed check refuses to start.
- Arguments are built by the daemon from a typed request. Config paths must be absolute, must resolve to regular files, and are passed as separate `-c` values. Each config file must be owned by the calling connection's uid (`NSXPCConnection.effectiveUserIdentifier`) or carry the world-readable bit; checked with `stat`. The TCP listen address is always `127.0.0.1:<port>` with port in 1024...65535. Extra flags are accepted only from this allowlist: `-n`/`--nodelay`, `-d`/`--debug`, `-t`/`--trace`, `-q`/`--quiet`, `--log-layer-changes`, `--release-grab-on-lock`, `--emergency-exit-code <int>`.
- The environment passed to kanata is fixed: `PATH=/usr/bin:/bin`, `HOME=/var/root`. Nothing from the client.
- No hooks, no shell, no environment, no executable path, no working directory are accepted over XPC.
- XPC connections are accepted only when they satisfy the code signing requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>" and identifier "io.jackyluong.barnata"`, set with `NSXPCConnection.setCodeSigningRequirement(_:)`.
- The only files the daemon writes are under `/Library/Logs/Barnata/` (dir 0755, log files 0644, root:wheel).
- The daemon never writes to `/etc`, never modifies launchd jobs other than its own children, and never touches the user's home directory.
- The only third-party binaries the daemon executes are the Karabiner daemon, manager, and pkg, each validated against `anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37"` first.

kanata itself reads a user-owned config file as root. With a `cmd`-less kanata build, a config file can only remap keys.

## Daemon plist

`Contents/Library/LaunchDaemons/io.jackyluong.barnata.daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.jackyluong.barnata.daemon</string>
  <key>BundleProgram</key>
  <string>Contents/MacOS/barnata-daemon</string>
  <key>MachServices</key>
  <dict>
    <key>io.jackyluong.barnata.daemon</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>io.jackyluong.barnata</string>
  </array>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>RunAtLoad</key>
  <false/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
```

launchd starts the daemon the first time a client connects to the Mach service. The daemon exits after 60 seconds with no running kanata and no connected clients. The virtual HID daemon child does not count toward idle and is stopped on idle exit. launchd starts the daemon again on the next connection. Nothing starts kanata at boot on its own; the app starts it at login through the `autorun` preset.

Registration from the app:

```swift
let daemon = SMAppService.daemon(plistName: "io.jackyluong.barnata.daemon.plist")
try daemon.register()
switch daemon.status {
case .enabled: break
case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
case .notRegistered, .notFound: // show error in menu
}
```

Approval happens once in System Settings > General > Login Items & Extensions with an admin credential prompt. The app re-checks `status` every time the menu opens and on app launch. The app never calls `unregister()` except from the deferred `--uninstall` command.

## Update flow

The daemon has no Info.plist of its own. `DaemonService.bundleVersion` reads `Contents/Info.plist` from the app bundle it sits in, so one `CFBundleVersion` covers both sides and the comparison below cannot drift.

On launch the app compares its `CFBundleVersion` with the daemon's `version()` reply. On mismatch:

1. Remember the daemon's current `presetName` if state is `running`.
2. Call `stop`, then `shutdown`. The daemon terminates its children and exits.
3. Reconnect with the usual backoff. launchd spawns the new binary from the updated bundle.
4. Start the remembered preset, or the `autorun` preset if none was running.

Kanata is also restarted when `DaemonStatus.kanataVersion` differs from the app's bundled kanata version string.

## XPC protocol

Mach service `io.jackyluong.barnata.daemon`. Interface in the shared `BarnataCore` module, all payload types `Codable` via a `Data`-wrapped JSON envelope.

```swift
@objc protocol BarnataDaemonProtocol {
  func version(reply: @escaping (String) -> Void)
  func status(reply: @escaping (Data) -> Void)                     // DaemonStatus
  func start(request: Data, reply: @escaping (Data) -> Void)       // StartRequest -> CommandResult
  func stop(reply: @escaping (Data) -> Void)                       // CommandResult
  func restart(reply: @escaping (Data) -> Void)                    // CommandResult, same request as last start
  func shutdown(reply: @escaping (Data) -> Void)                   // CommandResult, then the daemon exits
  func ensureVirtualHIDDaemon(reply: @escaping (Data) -> Void)     // CommandResult
  func installDriver(reply: @escaping (Data) -> Void)              // CommandResult
  func activateDriver(reply: @escaping (Data) -> Void)             // CommandResult
  func subscribe(client: NSXPCListenerEndpoint)                    // push status changes to the app
}

@objc protocol BarnataClientProtocol {
  func statusDidChange(status: Data)                               // DaemonStatus
}
```

```swift
struct StartRequest: Codable {
  var presetName: String
  var configPaths: [String]        // absolute
  var tcpPort: Int                 // 1024...65535
  var extraArgs: [String]          // allowlisted only
  var autorestartOnCrash: Bool
}

struct DaemonStatus: Codable {
  var daemonVersion: String
  var kanataVersion: String?
  var state: KanataState           // idle, starting, running, crashed, stopping
  var pid: Int32?
  var presetName: String?
  var configPaths: [String]
  var tcpPort: Int?
  var ownerUID: uid_t?             // uid of the connection that sent the last start
  var lastExitCode: Int32?
  var lastError: String?           // last 20 lines of kanata stderr after a non-zero exit
  var restartCount: Int
  var driver: DriverStatus
}

struct DriverStatus: Codable {
  var installed: Bool              // pkg files present under /Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice
  var version: String?             // from the Daemon.app Info.plist
  var requiredVersion: String
  var activated: Bool              // systemextensionsctl list shows the dext as activated and enabled
  var vhidDaemonRunning: Bool
  var vhidDaemonManagedByBarnata: Bool
}

struct CommandResult: Codable {
  var ok: Bool
  var message: String?
  var output: String?
}
```

Subscription: the app hands the daemon an anonymous listener endpoint. The daemon pushes `statusDidChange` on every state transition. The app also polls `status` when the menu opens. If the connection is invalidated the app reconnects with backoff (1 s, 2 s, 4 s, max 30 s).

## Process supervision in the daemon

- Spawn with `posix_spawn`, stdout and stderr redirected to `/Library/Logs/Barnata/kanata.log` (rotated at 5 MB, keep 3). The supervisor also keeps the last 20 lines of stderr in memory for `lastError`.
- Disclaim TCC responsibility for the child:

  ```swift
  // private symbol from libsystem
  @_silgen_name("responsibility_spawnattrs_setdisclaim")
  func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32
  ```

  Fallback if the symbol is missing or returns non-zero: spawn without it and report `responsibilityDisclaimed = false` in the log. In that case the grant attaches to `barnata-daemon` instead.

  With the disclaim in place, kanata is responsible for itself, and tccd resolves it up to the enclosing bundle. Confirmed from a live `tccd` log: a request from `io.jackyluong.barnata.kanata` produces `subject=io.jackyluong.barnata` at `/Applications/Barnata.app`. So the grant is made once, to the app, and the pane shows `Barnata` with its icon. Neither `kanata` nor `barnata-daemon` appears.

  kanata cannot raise the prompt itself: tccd logs `notifyUserOfDeniedAccessBy ... fails when requestor has UID 0` and denies silently. The app calls `AXIsProcessTrustedWithOptions` instead, which resolves to the same subject.

  Accessibility is the only grant Barnata asks for. It covers Input Monitoring as well. Measured on macOS 27: tccd has written only `kTCCServiceAccessibility` records for `io.jackyluong.barnata`, yet kanata's `kTCCServiceListenEvent` check answers `authValue=2` with `subject=io.jackyluong.barnata`, and it still answers `2` straight after `tccutil reset ListenEvent io.jackyluong.barnata`. No `Barnata` row appears under Input Monitoring because no Input Monitoring record exists. Before the Accessibility grant, kanata exited 1 with `kanata needs macOS Input Monitoring permission`; after it, kanata logs `keyboard grabbed`.

  Related findings:

  - The silent root-side denial is cached. Once recorded, `IOHIDCheckAccess` returns `denied` and the prompt never appears again. `tccutil reset ListenEvent io.jackyluong.barnata` clears that one entry. The app avoids creating the stale denial in the first place by refusing to autostart while the grant is missing, so kanata never runs and never asks from uid 0.
  - macOS 27 renamed the Accessibility pane to Device Control and Data Access. `SystemPaneNames` in `BarnataAppKit` picks the label at runtime from `ProcessInfo.isOperatingSystemAtLeast`, so the menu matches the pane on both macOS 14 and 27.
  - An app-side `IOHIDRequestAccess` on the unnotarized debug build is answered with `Refusing TCCAccessRequest for service kTCCServiceListenEvent ... due to security policy`. The app no longer makes that call.

  Unverified below macOS 27: whether Accessibility implies Input Monitoring on macOS 14 through 26. The permission rows in the settings window are driven by a runtime `AXIsProcessTrusted` check, so a system that needs a separate grant still shows kanata's own error in the title line.
- `stop` sends SIGTERM, waits 3 s, then SIGKILL. `stop` also stops the Barnata-managed virtual HID daemon.
- State after exit is decided by the exit code: non-zero sets `crashed`, zero sets `idle`. kanata emergency exit (LCtrl+Space+Esc) exits with code 0.
- With `autorestartOnCrash`, a `crashed` exit restarts with backoff (1 s, 2 s, 4 s, 8 s, cap 30 s). The daemon gives up after 5 restarts inside 2 minutes and stays `crashed`.
- On daemon exit for any reason, all children get SIGTERM, then SIGKILL if they are still alive. The exit blocks until they are gone: kanata does not always act on SIGTERM, and exiting first leaves it holding the keyboard and the TCP port.
- Single instance: `start` while running stops the current kanata first. At startup the daemon also kills any process running its own bundled kanata path, which reaps a child an earlier daemon left behind.
- The `ProcessSupervisor` takes a `Spawner` protocol so the backoff policy is testable without spawning.

## Karabiner virtual HID driver

kanata needs the `Karabiner-DriverKit-VirtualHIDDevice` system extension activated and the `Karabiner-VirtualHIDDevice-Daemon` process running as root. The signed pkg from pqrs is bundled at `Contents/Resources/Karabiner-DriverKit-VirtualHIDDevice-<DRIVER_VERSION>.pkg`.

`status` reports the driver state. `start` calls `ensureVirtualHIDDaemon` first:

1. If a process whose executable path is `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon` is already running (Karabiner-Elements or another manager owns it), do nothing.
2. Otherwise validate that binary against the pqrs requirement and spawn it as a supervised child with the same crash policy as kanata. It stops together with kanata.
3. If the binary is missing, return `ok = false` with a message telling the app to offer "Install driver…".

`installDriver`:

1. Refuse when an installed driver version is newer than `requiredVersion`. The message names both versions.
2. Verify the bundled pkg with `pkgutil --check-signature`, requiring a Developer ID Installer certificate for team `G43BCU2T37`.
3. Run `/usr/sbin/installer -pkg <bundled pkg> -target /`.
4. Run `activateDriver`.

`activateDriver` runs `/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate` after the signature check. The app then opens System Settings > General > Login Items & Extensions > Driver Extensions for the user's approval.

## kanata TCP client in the app

The app connects to `127.0.0.1:<tcpPort>` after the daemon reports `running`, retrying every 250 ms for 10 s. Newline-delimited JSON, one object per line.

Sent on connect: `{"Hello":{}}`, `{"RequestLayerNames":{}}`, `{"RequestCurrentLayerName":{}}`.

Used by menu actions:

| Menu action | Message |
|---|---|
| Switch layer | `{"ChangeLayer":{"new":"<name>"}}` |
| Reload config | `{"Reload":{}}` |
| Next config file | `{"ReloadNext":{}}` |
| Previous config file | `{"ReloadPrev":{}}` |

Handled server messages: `HelloOk`, `LayerChange`, `LayerNames`, `CurrentLayerName`, `ConfigFileReload`, `Error`, `ReloadResult`. Others are ignored. If a line contains `you sent an invalid message`, disconnect and reconnect without sending `Hello`.

## Menu

Status item icon reflects, in priority order: daemon not approved, driver missing, privacy grant missing, kanata crashed, `paused` while idle, reloading (2 s flash), current layer icon, default icon.

While state is `starting` or `stopping` for longer than 400 ms, the status item shows an `NSProgressIndicator` with `style = .spinning` in place of the icon. Shorter transitions keep the previous icon.

The status item uses `NSStatusItem.squareLength`, so its width never changes. Every image, bundled symbol or PNG override, is scaled to fit an 18 pt square, and the spinner is 16 pt centered in the same box.

Layer icons are SF Symbols from `IconCatalog` in `BarnataCore`. A `layer_icons` value outside that pool draws `exclamationmark.triangle.fill` in the status item and is flagged in the settings window.

```
Barnata: Running (example.kbd, layer: base)     disabled title line
------------------------------------------------
Presets
  ✓ Default                                       click to start, or stop when running
  Other preset
Layers                                            submenu, ✓ on the current layer
Reload config                                     ⌘R
Restart kanata
Stop kanata
------------------------------------------------
Open kanata log
Preferences…                                      ⌘, opens the settings window
------------------------------------------------
Quit Barnata                                    no shortcut, always stops kanata first
```

Title line variants: `Running (<config>, layer: <layer>)`, `Starting`, `Stopping`, `Not running`, `Crashed (exit <code>)`, `Running for another user`, `Daemon not approved`, `Driver not installed`, `Driver <installed> is newer than required <required>`, `Config error: <message>`, `<Accessibility> not granted`.

`Running for another user` appears when `DaemonStatus.ownerUID` differs from the app's uid. Only "Stop kanata" stays enabled in that state.

Implementation: AppKit `NSStatusItem` and `NSMenu` built from a `MenuState` value by `MenuBuilder`, which returns a plain `[MenuEntry]` tree before any AppKit object is created. Icons are `NSImage` with `isTemplate` set for files whose name ends in `Template` before the extension.

## Settings window

`Preferences…` opens one `NSWindow` holding a SwiftUI `SettingsView` driven by `SettingsModel`. The tab strip is a real `NSToolbar` with `window.toolbarStyle = .preference`, so it matches Finder Settings; SwiftUI fills only the content below it. Every change is written straight back to `config.toml` through `ConfigFileWriter`, and `ConfigWatcher` is told to ignore the resulting file event. The window is the only way to change these settings, so the config file is never revealed to the user.

**General tab.** Opens first. Daemon approval, the Accessibility grant, and the Karabiner driver, each with a status mark and the action that resolves it; `launch_at_login` and `show_dock_icon`; and Uninstall.

**Configs tab.** A list of config file references, one per `[presets."Name"]` table. Adding runs an `NSOpenPanel` and stores the chosen paths only; no file is copied or moved. The list label is the preset name, renaming rewrites the table header, and deleting removes the table. Selecting an entry shows its name, its file with a Show in Finder button, and its layers, read from the `.kbd` file by `KanataConfigScanner` with `include` forms followed. Each layer plus an "All other layers" row (the `*` key) takes an icon from the `IconCatalog` picker. A value outside the pool shows `exclamationmark.triangle.fill` next to the row, and its layer keeps whatever the file says until a new icon is picked.

**Uninstall.** A sheet with a text field that enables the button only when `UNINSTALL` is typed exactly. It stops kanata, unregisters the daemon and the login item, deletes `~/.config/barnata/`, moves `Barnata.app` to the Trash, then quits. Referenced kanata files are never touched.

`MainMenu` installs an App and Edit menu. A menu bar app draws no menu bar, but `NSApplication` still routes ⌘C, ⌘V, ⌘Z and ⌘W through `mainMenu`, which the settings window's text fields need.

## App startup sequence

1. Load `config.toml`. On parse error, show an error icon and the message in the title line. Keep running.
2. Apply `show_dock_icon` and `launch_at_login` if present.
3. Register the daemon. If `requiresApproval`, show the setup item and stop here until approved (poll every 5 s).
4. Connect XPC, fetch `status`. Run the update flow if versions differ.
5. If kanata is already running, adopt it: connect TCP, mark the matching preset as active.
6. Otherwise, if a preset has `autorun = true`, send `start` for it.

## Source layout

```
barnata/
  Package.swift
  Sources/
    BarnataCore/          Config parsing and writing, TOML line editor, XPC protocol types, argument allowlist, icon catalog, kanata layer scanner
    BarnataDaemonKit/     RequestValidator, ProcessSupervisor, Spawner, BackoffPolicy, SignatureCheck, DriverManager, LogWriter, XPCListener
    barnata-daemon/       main.swift only
    BarnataAppKit/        AppController, StatusItemController, MenuState, MenuBuilder, DaemonClient, KanataTCPClient, IconStore, ConfigWatcher, SetupActions, SettingsWindowController, SettingsModel, SettingsView, Uninstaller, MainMenu
    Barnata/              main.swift only
  Tests/
    BarnataCoreTests/
    BarnataDaemonKitTests/
    BarnataAppKitTests/
  Resources/
    Info-App.plist, daemon.plist, status-icons/, driver-requirements.json
  Scripts/
    vars.sh, fetch-kanata.sh, fetch-driver.sh, build-app.sh, sign.sh, notarize.sh, release.sh, dev-install.sh
  docs/
```

SwiftPM only. No Xcode project. `Scripts/build-app.sh` assembles the `.app` from the SwiftPM products. Swift 6 language mode, strict concurrency. `arm64` only.
