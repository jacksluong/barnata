# Barnata

Menu bar app for [kanata](https://github.com/jtroo/kanata) on macOS. kanata runs as root under a launchd daemon registered from the app bundle.

## Install

```sh
brew install --cask jacksluong/tap/barnata
```

## Build

```sh
source Scripts/vars.sh
swift build
swift test
```

## License

Barnata is licensed under the GNU General Public License version 3, in `LICENSE`.
