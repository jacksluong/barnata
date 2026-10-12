#!/bin/bash
# Notarizes build/Barnata.app and staples the ticket. make-dmg.sh packs the result.
# Requires the `barnata` notarytool keychain profile from Scripts/vars.sh.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

APP="${BUILD_DIR}/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "${APP} does not exist, run build-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
SUBMISSION_ZIP="${BUILD_DIR}/${APP_NAME}-submission.zip"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "no notarytool keychain profile named ${NOTARY_PROFILE}" >&2
  echo "run: xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <apple id> --team-id ${TEAM_ID}" >&2
  exit 1
fi

echo "==> Zipping for submission"
rm -f "$SUBMISSION_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMISSION_ZIP"

echo "==> Submitting to Apple"
if ! xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
  echo "notarization failed; the offending binary is named in:" >&2
  echo "  xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}" >&2
  exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$SUBMISSION_ZIP"

echo "==> Verifying Gatekeeper"
spctl --assess --type execute --verbose "$APP"

echo
echo "==> Notarized ${APP} version ${VERSION}"
