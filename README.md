# Barnata

Menu bar app for [kanata](https://github.com/jtroo/kanata) on macOS. kanata runs as root under a launchd daemon registered from the app bundle, with no sudoers entries.

Planning documents live in `docs/`, starting with `docs/README.md`.

## Install

```sh
brew install --cask jacksluong/tap/barnata
open -a Barnata
```

Apple silicon, macOS 14 or later. Settings live in `~/.config/barnata/config.toml`, which the app creates on first launch.

## Build

```sh
source Scripts/vars.sh
swift build
swift test
```

`swift test` requires the Xcode toolchain, which `Scripts/vars.sh` selects through `DEVELOPER_DIR`.

## License

Barnata is licensed under the GNU General Public License version 3, in `LICENSE`.

The bundled kanata binary, the bundled Karabiner driver installer, and the linked TOMLKit library
keep their own licenses. See `THIRD-PARTY-NOTICES.md`, which ships inside the app bundle at
`Contents/Resources/THIRD-PARTY-NOTICES.md` alongside a copy of `LICENSE`.
