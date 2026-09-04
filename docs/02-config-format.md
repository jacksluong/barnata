# 02. Config format

File: `~/.config/barnata/config.toml`. Override the location with the `BARNATA_CONFIG` environment variable (absolute path to a file). Icons live in `icons/` next to the config file. Relative icon paths resolve against that directory.

The config file is the single source of truth. The app never writes to it except for the two settings marked writable below, and only when their menu items are toggled.

## Schema

```toml
[app]
launch_at_login = true          # optional; absent leaves the system setting untouched. Writable by the menu.
show_dock_icon = false          # optional, default false. Writable by the menu.
status_icons = "status-icons"   # optional; directory with default/crashed/paused/reloading overrides

[defaults]                      # applied to every preset unless the preset overrides the key
tcp_port = 5829                 # 1024...65535
autorestart_on_crash = false
extra_args = []                 # allowlisted kanata flags only
layer_icons = {}                # layer name -> icon file, '*' is the fallback

[presets."Default"]             # table name is the preset name shown in the menu
kanata_config = "~/.config/kanata/canary.kbd"   # string or array of strings; array enables ReloadNext/ReloadPrev
autorun = true                  # at most one preset may set this
# tcp_port, autorestart_on_crash, extra_args, layer_icons may be overridden here
```

Rules:

- `~` at the start of a path expands to the home directory. Paths are resolved to absolute before being sent to the daemon.
- `kanata_config` files must exist when a preset is started. A missing file is reported in the menu, the preset stays selectable.
- `extra_args` entries outside the allowlist in `01-architecture.md` make the config invalid. The error names the flag.
- Preset order in the menu is the order in the file.
- Unknown keys are errors.
- `layer_icons` in a preset replaces the defaults table entirely.

## Full example matching the current setup

```toml
[app]
launch_at_login = true
show_dock_icon = false

[defaults]
tcp_port = 5829
autorestart_on_crash = false

[defaults.layer_icons]
base     = "base.png"
typing   = "typing.png"
arrows   = "arrows.png"
numbers  = "numbers.png"
launcher = "launcher.png"
system   = "system.png"
navcode  = "navcode.png"
modnums  = "modnums.png"
nohrm    = "nohrm.png"
"*"      = "default.png"

[presets."Default"]
kanata_config = "~/.config/kanata/canary.kbd"
autorun = true
```

## Not carried over from kanata-tray

- `general.allow_concurrent_presets`: one kanata process at a time.
- `general.control_server_*`: no HTTP control server. Use kanata's own TCP port for scripting.
- `defaults.kanata_executable` and `presets.*.kanata_executable`: the bundled binary is always used.
- `hooks`: no hooks in the first version. If added later they run inside the app as the user, never in the daemon.
- `extra_env`: no environment passthrough.

## Parsing

Use [TOMLKit](https://github.com/LebJe/TOMLKit) via SwiftPM. Decode into `Codable` structs in `BarnataCore`. Validation errors carry the TOML key path in the message.
