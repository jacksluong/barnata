# 06. Verification

## Debug commands

```
# daemon registration and state
launchctl print system/io.jackyluong.barnata.daemon
sudo launchctl print system/io.jackyluong.barnata.daemon | grep -E 'state|pid|last exit'

# login item and daemon approval as seen by SMAppService (from the app log)
log stream --predicate 'subsystem == "io.jackyluong.barnata"' --level debug

# kanata output
tail -f /Library/Logs/Barnata/kanata.log

# processes
ps -axo user,pid,ppid,command | grep -E 'kanata|Karabiner-VirtualHIDDevice-Daemon' | grep -v grep

# kanata TCP
(printf '{"Hello":{}}\n{"RequestLayerNames":{}}\n'; sleep 1) | nc -w 2 127.0.0.1 5829

# signatures
codesign -dv --verbose=2 /Applications/Barnata.app
codesign -dv --verbose=2 /Applications/Barnata.app/Contents/MacOS/kanata
spctl --assess --type execute --verbose /Applications/Barnata.app
pkgutil --check-signature /Applications/Barnata.app/Contents/Resources/Karabiner-DriverKit-VirtualHIDDevice-*.pkg

# driver
systemextensionsctl list | grep pqrs
```

## Checklist

Run in order on a machine that has never had Barnata or Karabiner-Elements. Items marked (this Mac) also run on the migration machine after `05-dotfiles-migration.md`.

Install

- [ ] `brew install --cask jacksluong/tap/barnata` places the app in `/Applications` with no Gatekeeper warning on first open.
- [ ] Opening the app from `~/Downloads` shows the "move to /Applications" alert and quits.

First launch

- [ ] With `~/.config/barnata/` absent, launching creates `config.toml` with `[app]` and `[defaults]`. The menu lists no presets and shows no config error.
- [ ] Menu bar icon appears. No Dock icon.
- [ ] Preferences opens the settings window. General shows "Background daemon" unapproved with an Approve button. Clicking opens Login Items. Approving asks for the admin password once.
- [ ] After approval the row turns green within 5 s with the window still open.
- [ ] General shows the Karabiner driver as not installed with an Install button. One click installs the pkg, no password, and System Settings opens on Driver Extensions. After allowing, the row turns green and `systemextensionsctl list` shows the dext activated.
- [ ] (this Mac) With Karabiner-Elements present, the driver row is already green and `DaemonStatus.driver.vhidDaemonManagedByBarnata` is false.
- [ ] Grant Accessibility shows the system prompt on a fresh Mac. The pane lists `Barnata` with its icon, not `kanata` or `barnata-daemon`.
- [ ] Once granted, the row turns green and the autorun preset starts within 5 s without relaunching the app.
- [ ] `log show --predicate 'process == "tccd"'` shows `subject=io.jackyluong.barnata` for a `kTCCServiceListenEvent` request from `io.jackyluong.barnata.kanata`, answered `authValue=2`, with no Barnata row in the Input Monitoring pane.
- [ ] If kanata still exits 1 with the Input Monitoring message, `tccutil reset ListenEvent io.jackyluong.barnata` clears a cached silent denial from a uid 0 request. Never a global `tccutil reset`.
- [ ] After the grant, the autorun preset starts and the keyboard is remapped. No password prompt.

Running

- [ ] Layers submenu lists all layers from `RequestLayerNames`. The current one has a checkmark.
- [ ] The status item never changes width: during start, during the stop spinner, and across every layer icon.
- [ ] Holding a layer key changes the menu bar icon to that layer's icon and back.
- [ ] Choosing a layer in the submenu switches to it.
- [ ] Reload config after editing the `.kbd` file applies the change, the icon flashes reloading.
- [ ] Reload with a syntax error keeps the old config running and shows the kanata error message in the menu title line.
- [ ] `kill -9 <kanata pid>` with `autorestart_on_crash = false` shows Crashed with the exit code. With `true`, kanata is back within 2 s and the restart count increments.
- [ ] Six `kill -9` inside 2 minutes with `autorestart_on_crash = true`: the daemon gives up and the menu shows Crashed.
- [ ] Start with a `.kbd` that has a parse error: menu title shows the kanata error text from `lastError`.
- [ ] Emergency exit (LCtrl+Space+Esc) shows Not running with the `paused` icon, no restart.
- [ ] Stop kanata, then start a different preset. Only one kanata process exists at any time.
- [ ] Stop kanata on a Mac without Karabiner-Elements: `Karabiner-VirtualHIDDevice-Daemon` exits too.
- [ ] Suspend kanata startup (`kill -STOP` the pid right after start): after 400 ms the status item shows a spinner; `kill -CONT` returns the layer icon.

Settings window

- [ ] The menu has `Preferences…` and no `Setup` submenu or `Open config file` item.
- [ ] The window opens on General, and the toolbar lists General before Configs.
- [ ] Adding a `.kbd` file through the + button creates a preset in `config.toml` and leaves `~/.config/barnata/` holding nothing but `config.toml` and `icons/`. The original file is neither moved nor copied.
- [ ] The added config lists every layer in the file, including layers in `include`d files.
- [ ] Renaming a config commits on Return and on clicking away, rewrites the preset header, keeps its icons, and renames it in the list and in the menu bar preset list.
- [ ] Deleting a config removes the preset and leaves the `.kbd` file on disk.
- [ ] Picking an icon for a layer writes an SF Symbol name into `[presets."<name>".layer_icons]` and the menu bar icon changes when that layer is active.
- [ ] A hand-written `layer_icons` value that is not in the pool shows `exclamationmark.triangle.fill` on the layer row and in the menu bar, and the value is left in the file until an icon is picked.
- [ ] Toggling Launch at login and Show in Dock writes the key and takes effect immediately.
- [ ] Editing `config.toml` in an editor while the window is open updates the window. The window itself never offers to open or reveal that file.
- [ ] A comment in `config.toml` survives every change made from the window.
- [ ] ⌘C, ⌘V, and ⌘A work in the name field.
- [ ] Uninstall is disabled until `UNINSTALL` is typed exactly. Lowercase and trailing spaces keep it disabled.
- [ ] Uninstall stops kanata, removes the daemon and login item, deletes `~/.config/barnata/`, moves the app to the Trash, and quits. The referenced `.kbd` files are still there.

App lifecycle

- [ ] Quit Barnata, by the menu item and by `killall Barnata`. Both stop kanata and remapping ends. The daemon exits within 60 s.
- [ ] After any daemon restart, `ps -axo pid,command | grep MacOS/kanata` lists exactly one kanata.
- [ ] Relaunch. The autorun preset starts and the menu shows Running with the right preset and layer within 5 s.
- [ ] Stop kanata and start the preset again five times over. The Layers submenu, the layer checkmark, and the layer icon return every time.
- [ ] Launch at login toggle is reflected in System Settings > Login Items and `launch_at_login` changes in `config.toml` with comments intact. Reboot: app is present, kanata starts without any prompt.
- [ ] Config file watcher: edit `config.toml`, the menu rebuilds. Break it, error shown, fix it, recovered.
- [ ] `show_dock_icon = true` in the file adds the Dock icon at once. `false` removes it. The menu toggle writes the file and the app log shows one reload, not two.

Security

- [ ] `/etc/sudoers.d` contains no kanata entries (this Mac).
- [ ] An ad-hoc signed copy of the app cannot connect to the daemon (connection invalidated, daemon log shows the rejection).
- [ ] Replacing `Contents/MacOS/kanata` with another binary makes `start` fail with a signature error and nothing is spawned.
- [ ] `start` with a config path that is a directory, a symlink to a directory, or a nonexistent file fails with a validation message.
- [ ] `start` with a config path owned by root and mode 0600 fails with an ownership message.
- [ ] `extra_args = ["--cfg-stdin"]` is rejected at config load.
- [ ] Replacing the bundled pkg with an unsigned pkg makes "Install driver…" fail with a signature error and nothing is installed.

Update

- [ ] Install a newer build over the old one. On launch kanata restarts once, `status` reports the new daemon version, and no password prompt appears.

Uninstall

- [ ] Quit Barnata, delete `/Applications/Barnata.app`. `launchctl print system/io.jackyluong.barnata.daemon` reports not found after the next login.
