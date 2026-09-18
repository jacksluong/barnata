# Scripts

| Script | What it does |
| --- | --- |
| `vars.sh` | Names, versions, and signing identity. Sourced by every other script. |
| `checksums.txt` | Expected sha256 of each downloaded artifact. |
| `fetch-kanata.sh` | Downloads the pinned kanata binary and checks it against `checksums.txt`. |
| `fetch-driver.sh` | Downloads the pinned Karabiner driver pkg, checks it against `checksums.txt`, and verifies its signature. |
| `build-app.sh` | Assembles `build/Barnata.app` from the SwiftPM products and signs it. Pass `--debug` for a debug build. |
| `sign.sh` | Signs the app bundle and everything nested in it. |
| `notarize.sh` | Sends the app to Apple, staples the ticket, and writes the release zip. |
| `dev-install.sh` | Replaces `/Applications/Barnata.app` with the local build and launches it. |
| `release.sh` | Runs the whole release: tag, build, sign, notarize, publish, bump the Homebrew cask. |
