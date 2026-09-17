# 05. Dotfiles migration

Repo `~/Developer/dotfiles`, chezmoi source root `home/`. Every path below is relative to `home/` unless it starts with `Brewfile` or `README.md`.

## Files to add

- `dot_config/barnata/config.toml`: the layout in `02-config-format.md`, one `Default` preset pointing at `~/.config/kanata/kanata.kbd`.
- `dot_config/barnata/icons/status-icons/*.png`: only if the bundled status icons need overriding. Layer icons are SF Symbols, so the nine layer PNGs from `private_Library/private_Application Support/kanata-tray/icons/` are not carried over.
- `.chezmoiscripts/run_once_after_40-kanata-tray-cleanup.sh`: removes the old setup on machines that had it. Idempotent; exits 0 when nothing is present.

  ```bash
  #!/bin/bash
  set -euo pipefail

  label="com.kanata-tray"
  plist="$HOME/Library/LaunchAgents/$label.plist"
  if [[ -f "$plist" ]]; then
    echo "==> Removing kanata-tray LaunchAgent"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$plist"
  fi

  for f in /etc/sudoers.d/kanata-tray /etc/sudoers.d/zz-kanata-tray; do
    if [[ -e "$f" ]]; then
      echo "==> Removing $f (needs sudo once)"
      sudo rm -f "$f"
    fi
  done

  if command -v brew &>/dev/null && brew list --formula kanata-tray &>/dev/null; then
    echo "==> Uninstalling kanata-tray"
    brew uninstall kanata-tray
  fi

  rm -rf "$HOME/Library/Application Support/kanata-tray"
  ```

- `.chezmoiscripts/run_onchange_after_50-barnata-launch.sh.tmpl`: launches the app after the config changes.

  ```bash
  #!/bin/bash
  # config.toml hash: {{ include (joinPath .chezmoi.sourceDir "dot_config/barnata/config.toml") | sha256sum }}
  set -euo pipefail

  if [[ -d /Applications/Barnata.app ]]; then
    echo "==> Launching Barnata"
    open -a Barnata
  else
    echo "barnata-launch: /Applications/Barnata.app is missing, skipping" >&2
  fi
  ```

Installing the app needs no script of its own. `run_onchange_before_30-brew-packages.sh.tmpl` already runs `brew bundle`, which installs the cask.

## Files to remove

- `private_Library/LaunchAgents/com.kanata-tray.plist`
- `private_Library/private_Application Support/kanata-tray/` (whole directory)
- `.chezmoiscripts/run_onchange_after_40-kanata-sudoers.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_50-launchagents.sh.tmpl`, since no plists remain under `private_Library/LaunchAgents/`

## Brewfile

```
+ tap "jacksluong/tap"
- brew "kanata-tray"
+ cask "barnata"
```

Keep `brew "kanata"`. It is used for editing and `kanata --check` from the shell and is not executed by Barnata.

`HOMEBREW_BUNDLE_NO_UPGRADE=1` is set in the brew script, so `brew bundle` installs Barnata but never upgrades it. `brew upgrade --cask barnata` is the upgrade path.

Karabiner-Elements is not in the Brewfile and stays optional. Barnata installs and runs the virtual HID driver itself when Karabiner-Elements is absent.

## Config edits by the app

Barnata writes `launch_at_login` and `show_dock_icon` back into `config.toml` when toggled from the menu. After such a toggle, `chezmoi re-add ~/.config/barnata/config.toml` records the change in the source state.

## Script order after the change

```
run_once_before_10-homebrew.sh
run_once_before_20-developer-dir.sh
run_onchange_before_30-brew-packages.sh.tmpl       installs the cask
run_once_before_40-ssh-github.sh.tmpl
run_once_before_50-standalone-tools.sh
run_once_after_10-vim-plugins.sh
run_once_after_20-clone-repos.sh.tmpl
run_after_30-dotfiles-repo.sh.tmpl
run_once_after_40-kanata-tray-cleanup.sh           new, replaces 40-kanata-sudoers
run_onchange_after_50-barnata-launch.sh.tmpl       new, replaces 50-launchagents
run_after_60-ai-skills.sh
run_onchange_after_70-mas-apps.sh.tmpl
run_once_after_80-macos-shortcuts.sh.tmpl
run_once_after_90-manual-steps.sh.tmpl             text updated
```

## `run_once_after_90-manual-steps.sh.tmpl` replacement text for the kanata section

```
  * Barnata: it launched at the end of `chezmoi apply`. Finish in
    Preferences, General tab, from its menu bar item:
      1. Approve background daemon (admin password once).
      2. If shown, Install Karabiner driver. One click installs and
         activates it; allow it in the System Settings pane that opens.
      3. Grant Accessibility. Clicking it shows the system prompt. It
         covers Input Monitoring too, so there is nothing else to grant.
    Kanata starts on its own once all three are done.
```

## README.md keyboard section replacement

```
[Barnata](https://github.com/jacksluong/barnata) runs it as a root launchd
daemon and shows a per-layer icon in the menu bar. Presets and icons are in
`home/dot_config/barnata/config.toml`, editable from the app's Preferences
window. First launch asks for one admin approval and the Accessibility grant
for the app.
```

## Order of operations on this machine

1. Make `jacksluong/barnata` public.
2. `Scripts/release.sh 0.1.0` to ship 0.1.0 and bump the cask.
3. Push `jacksluong/homebrew-tap`.
4. Apply the dotfiles change. The cleanup script asks for sudo once to delete the sudoers file. That is the last sudo prompt.
5. Finish the Permissions rows in Preferences.
6. Confirm `/etc/sudoers.d` is empty, `launchctl list | grep kanata-tray` is empty, and `ps aux | grep kanata` shows one `kanata` under `barnata-daemon`.
