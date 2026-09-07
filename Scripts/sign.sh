#!/bin/bash
# Signs build/Barnata.app inside-out with the Developer ID identity from vars.sh.
# --debug omits the secure timestamp, which release builds need for notarization.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

DEBUG_BUILD=0
[[ "${1:-}" == "--debug" ]] && DEBUG_BUILD=1

APP="${BUILD_DIR}/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "${APP} does not exist, run build-app.sh first" >&2; exit 1; }

COMMON=(--force --options runtime --sign "$SIGNING_IDENTITY")
[[ $DEBUG_BUILD -eq 1 ]] || COMMON+=(--timestamp)

sign_one() {
  local identifier="$1" target="$2"
  echo "==> Signing ${target#"$BUILD_DIR"/} as ${identifier}"
  codesign "${COMMON[@]}" --identifier "$identifier" "$target"
}

# Inside-out: nested executables first, the bundle last
sign_one "$KANATA_ID" "${APP}/Contents/MacOS/kanata"
sign_one "${BUNDLE_ID}.daemon" "${APP}/Contents/MacOS/barnata-daemon"
sign_one "$BUNDLE_ID" "${APP}/Contents/MacOS/${APP_NAME}"
sign_one "$BUNDLE_ID" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "${APP}/Contents/MacOS/kanata" 2>&1 | grep -E 'Identifier|TeamIdentifier'
echo "==> Signed ${APP}"
