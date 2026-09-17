# 05. Dotfiles migration

Repo `~/Developer/dotfiles`, chezmoi source root `home/`. Every path below is relative to `home/` unless it starts with `Brewfile` or `README.md`.

## Files to add

- `dot_config/barnata/config.toml`: the full example from `02-config-format.md`.
- `dot_config/barnata/icons/status-icons/*.png`: only if the bundled status icons need overriding. Layer icons are SF Symbols set in the settings window, so the nine layer PNGs from `private_Library/private_Application Support/kanata-tray/icons/` are not carried over.
- `.chezmoiscripts/run_once_after_46-barnata-install.sh`: installs or upgrades the app from the public GitHub release, or from the Homebrew cask in `04-distribution.md`.

  ```bash
  #!/bin/bash
  set -euo pipefail

  if [[ -d /Applications/Barnata.app ]]; then
    exit 0
  fi

  echo "==> Installing Barnata"
  tmp="$(mktemp -d)"
  gh release download --repo jacksluong/barnata --pattern 'Barnata-*.zip' --dir "$tmp" --clobber
  ditto -x -k "$tmp"/Barnata-*.zip /Applications
  rm -rf "$tmp"
  ```

- `.chezmoiscripts/run_once_after_47-kanata-tray-cleanup.sh`: removes the old setup on machines that had it. Idempotent; exits 0 when nothing is present.

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

- `.chezmoiscripts/run_onchange_after_49-barnata-launch.sh.tmpl`: launches the app after the config changes.

  ```bash
  #!/bin/bash
  # config hash: {{ include "dot_config/barnata/config.toml" | sha256sum }}
  set -euo pipefail
  if [[ -d /Applications/Barnata.app ]]; then
    echo "==> Launching Barnata"
    open -a Barnata
  fi
  ```

## Files to remove

- `private_Library/LaunchAgents/com.kanata-tray.plist`
- `private_Library/private_Application Support/kanata-tray/` (whole directory)
- `.chezmoiscripts/run_onchange_after_48-kanata-sudoers.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_50-reload-launchagents.sh.tmpl` if no plists remain under `private_Library/LaunchAgents/`

## Brewfile

```
- brew "kanata-tray"
```

Keep `brew "kanata"`. It is used for editing and `kanata --check` from the shell and is not executed by Barnata. Add `cask "barnata"` from the tap in `04-distribution.md`.

Karabiner-Elements is not in the Brewfile and stays optional. Barnata installs and runs the virtual HID driver itself when Karabiner-Elements is absent.

## Config edits by the app

Barnata writes `launch_at_login` and `show_dock_icon` back into `config.toml` when toggled from the menu. After such a toggle, `chezmoi re-add ~/.config/barnata/config.toml` records the change in the source state.

## Script order after the change

```
run_once_before_00-install-homebrew.sh
run_once_before_05-home-dirs.sh
run_onchange_before_10-brew-bundle.sh.tmpl
run_once_before_20-install-tools.sh
run_once_after_25-ssh-keys.sh.tmpl
run_once_after_30-vim-plugins.sh
run_once_after_45-dotfiles-git-hooks.sh
run_once_after_46-barnata-install.sh              new
run_once_after_47-kanata-tray-cleanup.sh          new
run_onchange_after_49-barnata-launch.sh.tmpl    new
run_once_after_99-manual-steps.sh                 text updated
```

## `run_once_after_99-manual-steps.sh` replacement text for the kanata section

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
[kanata](https://github.com/jtroo/kanata) remaps the built-in MacBook
keyboard to a Canary layout with home-row mods and nine layers (typing,
arrows, numbers, launcher, system, navcode, modnums, nohrm). The config is
`home/dot_config/kanata/canary.kbd`.

[Barnata](https://github.com/jacksluong/barnata) runs it as a root
launchd daemon and shows a per-layer icon in the menu bar. Presets and
icons are in `home/dot_config/barnata/config.toml`, editable from the
app's Preferences window. First launch asks for one admin approval and
the Accessibility grant for the app.
```

## Order of operations on this machine

1. Ship Barnata 0.1.0 as a GitHub release.
2. Apply the dotfiles change. The cleanup script asks for sudo once to delete the sudoers file. That is the last sudo prompt.
3. Finish the Permissions rows in Preferences.
4. Confirm `/etc/sudoers.d` is empty, `launchctl list | grep kanata-tray` is empty, and `ps aux | grep kanata` shows one `kanata` under `barnata-daemon`.
