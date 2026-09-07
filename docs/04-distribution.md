# 04. Distribution

## Signing

| Binary | Identifier | Flags |
|---|---|---|
| `Contents/MacOS/kanata` | `io.jackyluong.barnata.kanata` | `--options runtime --timestamp` |
| `Contents/MacOS/barnata-daemon` | `io.jackyluong.barnata.daemon` | `--options runtime --timestamp` |
| `Contents/MacOS/Barnata` and the bundle | `io.jackyluong.barnata` | `--options runtime --timestamp` |

All three use the same Developer ID Application identity. The daemon plist's `BundleProgram` target and the app must share the Team ID or `SMAppService` refuses registration. `Contents/Resources/*.pkg` is sealed as a resource and keeps its pqrs signature.

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

```
ditto -c -k --keepParent build/Barnata.app build/Barnata.zip
xcrun notarytool submit build/Barnata.zip --keychain-profile barnata --wait
xcrun stapler staple build/Barnata.app
ditto -c -k --keepParent build/Barnata.app build/Barnata-<version>.zip
```

On rejection, `xcrun notarytool log <id> --keychain-profile barnata` lists the offending binary. The usual cause is a binary without hardened runtime or without a timestamp.

## Release artifact

`Barnata-<version>.zip` attached to a GitHub release on `jacksluong/barnata`. No dmg. No pkg. The repo is private; downloads need `gh` authentication.

## Install on another Mac

```
gh release download --repo jacksluong/barnata --pattern 'Barnata-*.zip' --dir /tmp/barnata --clobber
ditto -x -k /tmp/barnata/Barnata-*.zip /Applications
open -a Barnata
```

The same three commands upgrade an existing install. `05-dotfiles-migration.md` wraps them in a chezmoi script.

The bundle must run from `/Applications`. Running from `~/Downloads` is refused by the app with an alert that names `/Applications`.

## Updating

Install the new version over the old one. On launch the app runs the update flow in `01-architecture.md`: stop kanata, ask the old daemon to shut down, reconnect to the new one, restart the preset. No re-approval, no password.

## Homebrew tap (deferred until the repo is public)

Repo `jacksluong/homebrew-tap`, file `Casks/barnata.rb`:

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

  zap trash: "~/.config/barnata"
end
```

`Scripts/release.sh` already prints the sha256. Bumping the cask is a manual commit to the tap.
