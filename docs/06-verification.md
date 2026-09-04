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

# driver
systemextensionsctl list | grep pqrs
```

## Checklist

Run in order on a machine that has never had Barnata. Items marked (this Mac) also run on the migration machine after `05-dotfiles-migration.md`.

Install

- [ ] `brew install --cask jacksluong/tap/barnata` places the app in `/Applications` with no Gatekeeper warning on first open.
- [ ] Opening the app from `~/Downloads` shows the "move to /Applications" alert and quits.

First launch

- [ ] Menu bar icon appears. No Dock icon.
- [ ] Setup shows "Approve background daemon…". Clicking opens Login Items. Approving asks for the admin password once.
- [ ] After approval the item disappears within 5 s without relaunching the app.
- [ ] Setup shows the driver items when the pkg is missing and hides them when installed and activated.
- [ ] Grant Input Monitoring reveals `/Applications/Barnata.app/Contents/MacOS/kanata` in Finder and opens the pane. Same for Accessibility.
- [ ] After grants, the autorun preset starts and the keyboard is remapped. No password prompt.

Running

- [ ] Layers submenu lists all layers from `RequestLayerNames`. The current one has a checkmark.
- [ ] Holding a layer key changes the menu bar icon to that layer's icon and back.
- [ ] Choosing a layer in the submenu switches to it.
- [ ] Reload config after editing the `.kbd` file applies the change, the icon flashes reloading.
- [ ] Reload with a syntax error keeps the old config running and shows the kanata error message in the menu title line.
- [ ] `kill -9 <kanata pid>` with `autorestart_on_crash = false` shows Crashed. With `true`, kanata is back within 2 s and the restart count increments.
- [ ] Emergency exit (LCtrl+Space+Esc) shows Not Running, no restart.
- [ ] Stop kanata, then start a different preset. Only one kanata process exists at any time.

App lifecycle

- [ ] Quit Barnata. Remapping continues. `barnata-daemon` and `kanata` are still running.
- [ ] Relaunch. Menu shows Running with the right preset and layer within 2 s. kanata pid unchanged.
- [ ] Quit and stop kanata. Remapping ends. The daemon exits within 60 s.
- [ ] Launch at login toggle is reflected in System Settings > Login Items. Reboot: app is present, kanata starts without any prompt.
- [ ] Config file watcher: edit `config.toml`, the menu rebuilds. Break it, error shown, fix it, recovered.
- [ ] `show_dock_icon = true` adds the Dock icon at once. `false` removes it.

Security

- [ ] `/etc/sudoers.d` contains no kanata entries (this Mac).
- [ ] An ad-hoc signed copy of the app cannot connect to the daemon (connection invalidated, daemon log shows the rejection).
- [ ] Replacing `Contents/MacOS/kanata` with another binary makes `start` fail with a signature error and nothing is spawned.
- [ ] `start` with a config path that is a directory, a symlink to a directory, or a nonexistent file fails with a validation message.
- [ ] `extra_args = ["--cfg-stdin"]` is rejected at config load.

Update

- [ ] Install a newer build over the old one. On launch the daemon is re-registered without a password prompt and `status` reports the new version.

Uninstall

- [ ] `brew uninstall --cask barnata` stops the daemon and removes the app. `launchctl print system/io.jackyluong.barnata.daemon` reports not found after the next login.
