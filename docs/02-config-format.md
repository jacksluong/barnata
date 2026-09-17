# 02. Config format

File: `~/.config/barnata/config.toml`. Override the location with the `BARNATA_CONFIG` environment variable (absolute path to a file). Barnata creates the file and its directory on the first read or write if they are absent, holding an empty `[app]` and `[defaults]`. Status icon overrides live in `icons/` next to the config file; relative `status_icons` paths resolve against that directory.

The config file is the single source of truth, for hand edits and for the settings window alike. Everything the settings window changes is written back here.

## Schema

```toml
[app]
launch_at_login = true          # optional; absent leaves the system setting untouched. Writable by the settings window.
show_dock_icon = false          # optional, default false. Writable by the settings window.
status_icons = "status-icons"   # optional; directory with default/crashed/paused/reloading overrides

[defaults]                      # applied to every preset unless the preset overrides the key
tcp_port = 5829                 # 1024...65535
autorestart_on_crash = false
extra_args = []                 # allowlisted kanata flags only
layer_icons = {}                # layer name -> SF Symbol name, '*' is the fallback

[presets."Default"]             # table name is the preset name shown in the menu
kanata_config = "~/.config/kanata/example.kbd"   # string or array of strings; array enables ReloadNext/ReloadPrev
autorun = true                  # at most one preset may set this
# tcp_port, autorestart_on_crash, extra_args, layer_icons may be overridden here
```

Rules:

- `~` at the start of a path expands to the home directory. Paths are resolved to absolute before being sent to the daemon.
- `kanata_config` files must exist when a preset is started. A missing file is flagged in the settings window, the preset stays selectable.
- `extra_args` entries outside the allowlist in `01-architecture.md` make the config invalid. The error names the flag.
- Preset order in the menu is the order in the file.
- Unknown keys are errors.
- `layer_icons` in a preset replaces the defaults table entirely. The settings window always writes into the preset, copying the inherited defaults in on the first edit.
- `layer_icons` values are SF Symbol names from `IconCatalog` in `BarnataCore`. Anything else is shown as `exclamationmark.triangle.fill` in the menu bar and flagged in the settings window. Invalid values are left in the file until an icon is picked.
- Each config file added through the settings window becomes one preset holding one `kanata_config` path. Hand-written presets with several paths keep working and show all their paths.

## Writing

`TOMLDocument` in `BarnataCore` holds the file as its own lines and edits those lines, so comments, key order, and spacing outside the edited key survive every write. `ConfigWriter` layers the config-specific operations on top of it, and `ConfigFileWriter` does the atomic write (temp file plus rename) and returns the resulting modification date. `ConfigWatcher` ignores the next change event whose modification date equals that one.

| Operation | Effect on the file |
|---|---|
| Set `launch_at_login` or `show_dock_icon` | Replace the value on the existing line in `[app]`, keeping indentation and any trailing comment. Append the key to the table if absent, or insert `[app]` at the top of the file if the table is absent. |
| Add a config file | Append `[presets."Name"]` with one `kanata_config` line, after the presets already in the file. |
| Rename a config file | Rewrite the `[presets."Old"]` header and the header of every table nested under it. |
| Delete a config file | Remove the preset header, its body, and its nested tables. |
| Set a layer icon | Set the key in `[presets."Name".layer_icons]`, creating that sub-table under its preset. An inline `layer_icons = { … }` is normalized into the sub-table first. |
| Clear a layer icon | Remove the key from `[presets."Name".layer_icons]`. |

Preset names are always written quoted. Layer names are written bare when they are valid bare keys, so the `*` fallback is written `"*"`.

## Full example matching the current setup

```toml
[app]
launch_at_login = true
show_dock_icon = false

[defaults]
tcp_port = 5829
autorestart_on_crash = false

[presets."Default"]
kanata_config = "~/.config/kanata/example.kbd"
autorun = true

[presets."Default".layer_icons]
base     = "command"
typing   = "keyboard"
arrows   = "arrow.up.arrow.down"
numbers  = "number"
launcher = "square.grid.2x2"
system   = "gearshape"
navcode  = "chevron.left.forwardslash.chevron.right"
modnums  = "textformat.123"
nohrm    = "hand.raised"
"*"      = "command.circle"
```

## Not carried over from kanata-tray

- `general.allow_concurrent_presets`: one kanata process at a time.
- `general.control_server_*`: no HTTP control server. Use kanata's own TCP port for scripting.
- `defaults.kanata_executable` and `presets.*.kanata_executable`: the bundled binary is always used.
- `hooks`: no hooks in the first version. If added later they run inside the app as the user, never in the daemon.
- `extra_env`: no environment passthrough.

## Parsing

Use [TOMLKit](https://github.com/LebJe/TOMLKit) via SwiftPM for reading only. Decode into structs in `BarnataCore`. Validation errors carry the TOML key path in the message.
