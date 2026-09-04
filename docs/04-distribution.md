# 04. Distribution

## Signing

| Binary | Identifier | Flags |
|---|---|---|
| `Contents/MacOS/kanata` | `io.jackyluong.barnata.kanata` | `--options runtime --timestamp` |
| `Contents/MacOS/barnata-daemon` | `io.jackyluong.barnata.daemon` | `--options runtime --timestamp` |
| `Contents/MacOS/Barnata` and the bundle | `io.jackyluong.barnata` | `--options runtime --timestamp` |

All three use the same Developer ID Application identity. The daemon plist's `BundleProgram` target and the app must share the Team ID or `SMAppService` refuses registration.

No entitlements files. The app is not sandboxed. Hardened runtime is on for every binary.

`Info.plist` for the app:

```
CFBundleIdentifier          io.jackyluong.barnata
CFBundleName                Barnata
CFBundleExecutable          Barnata
CFBundlePackageType         APPL
CFBundleShortVersionString  <git describe --tags>
CFBundleVersion             <commit count>
LSMinimumSystemVersion      14.0
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

`Barnata-<version>.zip` attached to a GitHub release on `jacksluong/barnata`. No dmg. No pkg.

## Homebrew tap

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

  app "Barnata.app"

  uninstall launchctl: "io.jackyluong.barnata.daemon",
            quit:      "io.jackyluong.barnata"

  zap trash: [
    "~/.config/barnata",
    "~/Library/Logs/Barnata",
  ]
end
```

`Scripts/release.sh` prints the two lines to update (`version`, `sha256`). Bumping the cask is a manual commit to the tap.

Install on any Mac:

```
brew install --cask jacksluong/tap/barnata
```

Homebrew places the app in `/Applications`. The bundle must run from `/Applications`.

## Manual install without Homebrew

Download the zip, unzip, drag `Barnata.app` to `/Applications`, open it. Running from `~/Downloads` is refused by the app with an alert that names `/Applications`.

## Updating

Install the new version over the old one. On launch the app sees the daemon version mismatch, calls `unregister()` then `register()`, and the next `start` uses the new daemon. Kanata is restarted by the app after an update when the bundled kanata version changed; the app compares `DaemonStatus.kanataVersion` to its own bundled version string.
