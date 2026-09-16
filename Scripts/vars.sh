# Single source of truth for names, versions, and signing. Sourced by every script.

APP_NAME="Barnata"
BUNDLE_ID="io.jackyluong.barnata"
DAEMON_LABEL="${BUNDLE_ID}.daemon"
KANATA_ID="${BUNDLE_ID}.kanata"

TEAM_ID="EE3526PL64"
SIGNING_IDENTITY="E20ADF15A9A4E3839E3E0D9BC60B5DBE81BD2F8D"   # Developer ID Application: Jacky Luong, expires 2031-09-05
NOTARY_PROFILE="barnata"

KANATA_VERSION="1.12.0"
DRIVER_VERSION="6.8.0"
DRIVER_PKG_URL="https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v${DRIVER_VERSION}/Karabiner-DriverKit-VirtualHIDDevice-${DRIVER_VERSION}.pkg"

# swift test needs XCTest and the swift-testing macro plugin, neither of which ships with Command Line Tools
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# BASH_SOURCE is bash-only; $0 covers zsh
VARS_SELF="${BASH_SOURCE[0]:-$0}"
REPO_ROOT="$(cd "$(dirname "$VARS_SELF")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"

# Compares a downloaded file against the sha256 recorded in checksums.txt for that name
verify_sha256() {
  local file_path="$1" recorded_name="$2"
  local expected actual
  expected="$(awk -v name="$recorded_name" '$2 == name { print $1 }' "${REPO_ROOT}/Scripts/checksums.txt")"
  if [[ -z "$expected" ]]; then
    echo "no sha256 recorded for ${recorded_name} in Scripts/checksums.txt" >&2
    return 1
  fi
  actual="$(shasum -a 256 "$file_path" | awk '{ print $1 }')"
  if [[ "$actual" != "$expected" ]]; then
    echo "sha256 mismatch for ${recorded_name}" >&2
    echo "  expected ${expected}" >&2
    echo "  actual   ${actual}" >&2
    return 1
  fi
  echo "==> sha256 verified for ${recorded_name}"
}
