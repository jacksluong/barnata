# Barnata

Menu bar app for [kanata](https://github.com/jtroo/kanata) on macOS. kanata runs as root under a launchd daemon registered from the app bundle, with no sudoers entries.

Planning documents live in `docs/`, starting with `docs/README.md`.

## Build

```sh
source Scripts/vars.sh
swift build
swift test
```

`swift test` requires the Xcode-beta toolchain, which `Scripts/vars.sh` selects through `DEVELOPER_DIR`.
