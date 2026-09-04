# Barnata implementation plan

Barnata is a from-scratch macOS menu bar app that runs and controls [kanata](https://github.com/jtroo/kanata). It replaces the current kanata-tray plus passwordless-sudoers setup. This directory is the complete plan for building it. Work the files in order.

| File | Contents |
|---|---|
| `01-architecture.md` | Components, privilege boundary, XPC and TCP protocols, process lifecycle |
| `02-config-format.md` | The `config.toml` schema with a full example |
| `03-implementation-steps.md` | Ordered build phases with acceptance criteria |
| `04-distribution.md` | Signing, notarization, Homebrew tap, release script |
| `05-dotfiles-migration.md` | Changes to the `dotfiles` chezmoi repo, removal of the sudoers rule |
| `06-verification.md` | Manual test checklist and debugging commands |

## Naming

The name `Barnata`, bundle id `io.jackyluong.barnata`, and Team ID are build-time variables in one place (`Scripts/vars.sh`). Change them there only.

| Item | Value |
|---|---|
| App name | Barnata |
| App bundle id | `io.jackyluong.barnata` |
| Daemon label and Mach service | `io.jackyluong.barnata.daemon` |
| Log subsystem | `io.jackyluong.barnata` |
| Repo | `~/Developer/barnata` (new, standalone, no code from kanata-tray) |
| Config file | `~/.config/barnata/config.toml` |
| Daemon state and logs | `/Library/Application Support/Barnata/`, `/Library/Logs/Barnata/` |

## Hard requirements

- macOS only. Deployment target macOS 14.
- kanata runs as root under a launchd daemon that is registered from the app bundle with `SMAppService`. No sudoers entries, no `sudo` anywhere.
- One admin authorization at first install (approving the daemon in System Settings). Nothing asks for a password after that, including at login.
- The menu bar app runs as the user with no privileges. Quitting it never stops kanata. Relaunching it reattaches.
- The app can be a login item with no password prompt.
- Config key `show_dock_icon` controls whether the app appears in the Dock. Default is menu bar only.
- Presets, kanata config paths, and layer icons come from a TOML file.
- The daemon never executes a path, environment, or shell command supplied by the unprivileged side. It only executes the kanata binary inside its own signed bundle, with an allowlisted argument set.
- The bundled kanata is the release build compiled without `cmd` support.
- Signed with Developer ID, hardened runtime, notarized, stapled. Installs on any Mac by Homebrew cask or by dragging to `/Applications`.
- Not a fork of kanata-tray. No Go, no shared code.

## Current state of the machine this replaces

Gathered on 2026-09-04 from `~/dotfiles` and the running system.

- kanata 1.12.0 from Homebrew at `/opt/homebrew/bin/kanata`, compiled without `cmd`. Running as root with `-c /Users/jackyluong/.config/kanata/canary.kbd --port 5829`.
- kanata-tray from Homebrew, started by `~/Library/LaunchAgents/com.kanata-tray.plist` with `ProgramArguments = [sudo, /opt/homebrew/bin/kanata-tray]`, `KeepAlive = true`.
- `/etc/sudoers.d/kanata-tray` grants `NOPASSWD:SETENV` for the kanata-tray binary, pinned by sha256, installed by `run_onchange_after_48-kanata-sudoers.sh.tmpl`.
- kanata-tray config at `~/Library/Application Support/kanata-tray/kanata-tray.toml` with one preset (`Default Preset`, autorun) and nine layer icons in `icons/`.
- Karabiner-Elements 16.2.0 is installed. Its SMAppService-registered daemons run `Karabiner-VirtualHIDDevice-Daemon` (driver 6.8.0) as root at boot. The daemon plist lives in `/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons v2.app/Contents/Library/LaunchDaemons/`.
- kanata TCP server on port 5829 answers `Hello` with protocol 1 and capabilities `reload, layer-names, fake-key-names, layer-change, hold-activated, tap-activated, current-layer-name, current-layer-info, fake-key, set-mouse`. Layer names: `base, typing, arrows, numbers, launcher, system, navcode, modnums, nohrm`.
- Both `kanata` and `kanata-tray` are granted Input Monitoring and Accessibility.
- Toolchain: Swift 6.4 command line tools, `Xcode-beta.app` in `/Applications`, `xcode-select` points at the command line tools. `notarytool` is available. No code signing identities exist yet.
- The user is enrolled in the Apple Developer Program with no certificates created.

## Version coupling to track

| kanata | Karabiner-DriverKit-VirtualHIDDevice |
|---|---|
| 1.12.x | 6.x |
| 1.13.0 and later | 8.0.0 |

The bundled kanata version and the required driver version are pinned together in `Scripts/vars.sh`.
