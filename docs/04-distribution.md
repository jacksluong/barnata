# 04. Distribution

## Signing

| Binary | Identifier | Flags |
|---|---|---|
| `Contents/MacOS/kanata` | `io.jackyluong.barnata.kanata` | `--options runtime --timestamp` |
| `Contents/MacOS/barnata-daemon` | `io.jackyluong.barnata.daemon` | `--options runtime --timestamp` |
| `Contents/MacOS/Barnata` and the bundle | `io.jackyluong.barnata` | `--options runtime --timestamp` |

All three use the same Developer ID Application identity. The daemon plist's `BundleProgram` target and the app must share the Team ID or `SMAppService` refuses registration. `Contents/Resources/*.pkg` is sealed as a resource and keeps its pqrs signature. `Contents/Resources/LICENSE` and `Contents/Resources/THIRD-PARTY-NOTICES.md` are sealed the same way.

No entitlements files. The app is not sandboxed. Hardened runtime is on for every binary. `arm64` only.

Two build flavors:

| Flavor | Command | Signing | Notarized | Use |
|---|---|---|---|---|
| debug | `Scripts/build-app.sh --debug` then `Scripts/dev-install.sh` | Developer ID, no timestamp | no | local loop on this Mac |
| release | `Scripts/release.sh` | Developer ID, timestamp | yes, stapled | any Mac |

`Info.plist` for the app:

```
CFBundleIdentifier          io.jackyluong.barnata
CFBundleName                Barnata
CFBundleExecutable          Barnata
CFBundlePackageType         APPL
CFBundleShortVersionString  <git describe --tags>
CFBundleVersion             <commit count>
LSMinimumSystemVersion      14.0
LSArchitecturePriority      arm64
LSUIElement                 true
NSHumanReadableCopyright    Jacky Luong
```

`Info.plist` for the daemon is embedded with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist` and carries `CFBundleIdentifier io.jackyluong.barnata.daemon` and the same version keys. The app compares its version to the daemon's `version()` reply.

## Notarization

`Scripts/notarize.sh` zips `build/Barnata.app`, submits it with `--keychain-profile barnata --wait`, staples the ticket, writes `build/Barnata-<version>.zip`, and prints its sha256. The version comes from the built `Info.plist`.

On rejection, `xcrun notarytool log <id> --keychain-profile barnata` lists the offending binary. The usual cause is a binary without hardened runtime or without a timestamp.

## Release

`Scripts/release.sh <version>` runs the whole sequence: refuse a dirty tree, `swift test`, tag `v<version>`, `build-app.sh`, `notarize.sh`, push the tag, `gh release create` with the zip attached, then bump `version` and `sha256` in the local tap checkout. `--dry-run` stops after notarization and deletes the tag.

The tag has to exist before the build, because `build-app.sh` reads the version back out of `git describe`.

## Release artifact

`Barnata-<version>.zip` attached to a GitHub release on `jacksluong/barnata`. No dmg. No pkg. It exists so the cask has something to download.

## Install on another Mac

```
brew install --cask jacksluong/tap/barnata
open -a Barnata
```

`brew upgrade --cask barnata` upgrades an existing install. `05-dotfiles-migration.md` wraps both in a chezmoi script.

The bundle must run from `/Applications`. Running from `~/Downloads` is refused by the app with an alert that names `/Applications`.

## Updating

Install the new version over the old one. On launch the app runs the update flow in `01-architecture.md`: stop kanata, ask the old daemon to shut down, reconnect to the new one, restart the preset. No re-approval, no password.

## Homebrew tap

A cask, not a formula. The released zip is already signed, notarized, and stapled.

Repo `jacksluong/homebrew-tap`, file `Casks/barnata.rb`, checked out locally at `TAP_DIR` (`~/Developer/homebrew-tap` by default):

```ruby
cask "barnata" do
  version "0.1.0"
  sha256 "<sha256 of the zip>"

  url "https://github.com/jacksluong/barnata/releases/download/v#{version}/Barnata-#{version}.zip"
  name "Barnata"
  desc "Menu bar app that runs and controls kanata"
  homepage "https://github.com/jacksluong/barnata"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Barnata.app"

  uninstall launchctl: "io.jackyluong.barnata.daemon",
            quit:      "io.jackyluong.barnata"

  zap trash: [
    "~/.config/barnata",
    "/Library/Logs/Barnata",
  ]
end
```

`Scripts/release.sh` rewrites the `version` and `sha256` lines. Committing and pushing the tap stays manual.

## Licensing

Barnata is GPL-3.0, in `LICENSE` at the repo root.

`Scripts/build-app.sh` copies `LICENSE` to `Contents/Resources/LICENSE` and renders `THIRD-PARTY-NOTICES.md` to `Contents/Resources/THIRD-PARTY-NOTICES.md`, substituting `__KANATA_VERSION__` and `__DRIVER_VERSION__` from `Scripts/vars.sh`, `__TOMLKIT_VERSION__` from `Package.resolved`, and `__TOMLPP_VERSION__` from the vendored `toml.hpp`.

| Component | License | Obligation met by |
|---|---|---|
| Barnata | GPL-3.0 | `LICENSE` in the bundle, source at `jacksluong/barnata` |
| kanata | LGPL-3.0 | LGPL-3.0 text in the notices, GPL-3.0 text in `LICENSE`, source link to the pinned tag next to the binary |
| Karabiner-DriverKit-VirtualHIDDevice | Unlicense | Unlicense text in the notices |
| TOMLKit and vendored toml++ | MIT | Copyright lines and MIT text in the notices |

kanata is spawned as a separate process and driven over TCP. It is never linked, so LGPL-3.0 section 4 does not apply and Barnata stays a separate work. Linking kanata's library crate instead would change that.

A kanata or driver version bump in `Scripts/vars.sh` moves the notices with it. A TOMLKit bump in `Package.resolved` does too. Neither needs an edit to `THIRD-PARTY-NOTICES.md`.
