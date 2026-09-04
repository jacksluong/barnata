# 01. Architecture

## Components

```
Barnata.app/
  Contents/
    Info.plist                       LSUIElement = true
    MacOS/
      Barnata                      menu bar app, runs as the user
      barnata-daemon               root daemon, registered via SMAppService
      kanata                         upstream release binary, re-signed
    Library/LaunchDaemons/
      io.jackyluong.barnata.daemon.plist
    Resources/
      status-icons/                  default, crashed, paused, reloading (template PNGs)
      driver-requirements.json       required Karabiner driver version and pkg URL
```

Three processes:

| Process | User | Lifetime | Job |
|---|---|---|---|
| `Barnata` | you | while the menu bar item is shown | menu, icons, config file, TCP client to kanata, XPC client to daemon |
| `barnata-daemon` | root | launched on demand by launchd, exits when idle | spawns and supervises kanata and, when needed, the Karabiner virtual HID daemon |
| `kanata` | root | child of the daemon | key remapping, TCP server on localhost |

## Privilege boundary

The daemon is the only code that runs as root and is written by this project. Rules it enforces on every request:

- The kanata executable is always `<own bundle>/Contents/MacOS/kanata`. The path is derived from the daemon's own executable path, never from the request.
- Before every spawn, the daemon validates the kanata binary with `SecStaticCodeCheckValidity` against the designated requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>" and identifier "io.jackyluong.barnata.kanata"`. A failed check refuses to start.
- Arguments are built by the daemon from a typed request. Config paths must be absolute, must resolve to regular files, and are passed as separate `-c` values. The TCP listen address is always `127.0.0.1:<port>` with port in 1024...65535. Extra flags are accepted only from this allowlist: `-n`/`--nodelay`, `-d`/`--debug`, `-t`/`--trace`, `-q`/`--quiet`, `--log-layer-changes`, `--release-grab-on-lock`, `--emergency-exit-code <int>`.
- The environment passed to kanata is fixed: `PATH=/usr/bin:/bin`, `HOME=/var/root`. Nothing from the client.
- No hooks, no shell, no environment, no executable path, no working directory are accepted over XPC.
- XPC connections are accepted only when they satisfy the code signing requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>" and identifier "io.jackyluong.barnata"`, set with `NSXPCConnection.setCodeSigningRequirement(_:)`.
- Files the daemon writes are under `/Library/Application Support/Barnata/` (mode 0755, root:wheel) and `/Library/Logs/Barnata/` (dir 0755, log files 0644).
- The daemon never writes to `/etc`, never modifies launchd jobs other than its own children, and never touches the user's home directory.

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

launchd starts the daemon the first time a client connects to the Mach service. The daemon exits after 60 seconds with no running child and no connected clients. launchd starts it again on the next connection. Nothing starts kanata at boot on its own; the app starts it at login through the `autorun` preset.

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

Approval happens once in System Settings > General > Login Items & Extensions with an admin credential prompt. The app re-checks `status` every time the menu opens and on app launch.

When the app's bundle version differs from the daemon's reported version, the app calls `unregister()` then `register()`.

## XPC protocol

Mach service `io.jackyluong.barnata.daemon`. Interface in the shared `BarnataCore` module, all payload types `Codable` and `NSSecureCoding` via a `Data`-wrapped JSON envelope.

```swift
@objc protocol BarnataDaemonProtocol {
  func version(reply: @escaping (String) -> Void)
  func status(reply: @escaping (Data) -> Void)                     // DaemonStatus
  func start(request: Data, reply: @escaping (Data) -> Void)       // StartRequest -> CommandResult
  func stop(reply: @escaping (Data) -> Void)                       // CommandResult
  func restart(reply: @escaping (Data) -> Void)                    // CommandResult, same request as last start
  func checkConfig(request: Data, reply: @escaping (Data) -> Void) // runs kanata --check, returns CommandResult with stderr
  func ensureVirtualHIDDaemon(reply: @escaping (Data) -> Void)     // CommandResult
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
  var lastExitCode: Int32?
  var lastError: String?
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

- Spawn with `posix_spawn`, stdout and stderr redirected to `/Library/Logs/Barnata/kanata.log` (rotated at 5 MB, keep 3).
- Disclaim TCC responsibility for the child:

  ```swift
  // private symbol from libsystem
  @_silgen_name("responsibility_spawnattrs_setdisclaim")
  func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32
  ```

  Fallback if the symbol is missing or returns non-zero: spawn without it and report `responsibilityDisclaimed = false` in the log. In that case both the daemon and kanata need Input Monitoring and Accessibility grants.
- `stop` sends SIGTERM, waits 3 s, then SIGKILL.
- Crash handling: exit within 60 s of start or a non-zero exit sets state `crashed`. With `autorestartOnCrash`, restart with backoff (1 s, 2 s, 4 s, 8 s, cap 30 s) and give up after 5 restarts inside 2 minutes.
- kanata emergency exit (LCtrl+Space+Esc) exits with code 0. State becomes `idle`, no restart.
- On daemon exit for any reason, all children get SIGTERM.
- Single instance: `start` while running stops the current kanata first.

## Karabiner virtual HID daemon

kanata needs the `Karabiner-DriverKit-VirtualHIDDevice` system extension activated and the `Karabiner-VirtualHIDDevice-Daemon` process running as root.

`status` reports the driver state. `start` calls `ensureVirtualHIDDaemon` first:

1. If a process whose executable path is `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon` is already running (Karabiner-Elements or another manager owns it), do nothing.
2. Otherwise validate that binary against `anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37"` and spawn it as a supervised child with the same crash policy as kanata. It stays up as long as the daemon stays up.
3. If the binary is missing, return a `CommandResult` with `ok = false` and a message pointing at the pkg URL from `driver-requirements.json`.

`activateDriver` runs `/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate` after the same signature check, then returns. The user still approves the extension in System Settings > General > Login Items & Extensions > Driver Extensions.

Installing the pkg itself is out of scope for the daemon. The app's "Install driver" menu item opens the pkg download URL.

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

Status item icon reflects, in priority order: daemon not approved, driver missing, kanata crashed, reloading (2 s flash), current layer icon, default icon.

```
Barnata: Running (canary.kbd, layer: base)     disabled title line
------------------------------------------------
Presets
  ✓ Default                                       click to start, or stop when running
  Other preset
Layers                                            submenu, ✓ on the current layer
Reload config                                     ⌘R
Restart kanata
Stop kanata
------------------------------------------------
Open config file                                  opens config.toml in the default editor
Open kanata log
Open Barnata log                                Console.app filtered to the subsystem
Setup                                             submenu
  Approve background daemon…                      shown until daemon.status == .enabled
  Install Karabiner driver…                       shown when driver not installed
  Activate Karabiner driver                       shown when installed but not activated
  Grant Input Monitoring…                         opens the pane and reveals kanata in Finder
  Grant Accessibility…
  Launch at login                                 checkmark, toggles SMAppService.mainApp
  Show in Dock                                    checkmark, applies immediately, persists to config
------------------------------------------------
Quit Barnata                                    ⌘Q, kanata keeps running
Quit and stop kanata
```

Implementation: AppKit `NSStatusItem` and `NSMenu` built from a `MenuState` value. No SwiftUI windows in the first version. Icons are `NSImage` with `isTemplate` set for files whose name ends in `Template` before the extension.

## App startup sequence

1. Load `config.toml`. On parse error, show an error icon and an "Open config file" item. Keep running.
2. Apply `show_dock_icon` and `launch_at_login` if present.
3. Register the daemon. If `requiresApproval`, show the setup item and stop here until approved (poll every 5 s).
4. Connect XPC, fetch `status`.
5. If kanata is already running, adopt it: connect TCP, mark the matching preset as active.
6. Otherwise, if a preset has `autorun = true`, send `start` for it.

## Source layout

```
barnata/
  Package.swift
  Sources/
    BarnataCore/          Config parsing, XPC protocol types, argument allowlist, icon lookup
    Barnata/              AppKit app: AppDelegate, StatusItemController, MenuBuilder, DaemonClient, KanataTCPClient, IconStore
    barnata-daemon/       main.swift, XPCListener, ProcessSupervisor, SignatureCheck, DriverManager, LogWriter
  Tests/
    BarnataCoreTests/
  Resources/
    Info-App.plist, Info-Daemon.plist, daemon.plist, entitlements, status-icons/
  Scripts/
    vars.sh, fetch-kanata.sh, build-app.sh, sign.sh, notarize.sh, release.sh
  docs/
```

SwiftPM only. No Xcode project. `Scripts/build-app.sh` assembles the `.app` from the SwiftPM products. Swift 6 language mode, strict concurrency.
