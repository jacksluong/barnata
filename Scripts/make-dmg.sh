#!/bin/bash
# Packs the stapled build/Barnata.app into build/Barnata-<version>.dmg, then signs, notarizes, and staples the DMG.
# Run notarize.sh first so the app inside carries its own ticket.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

APP="${BUILD_DIR}/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "${APP} does not exist, run build-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/barnata-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging ${APP_NAME}.app and an Applications shortcut"
ditto "$APP" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"

echo "==> Creating ${DMG#"$BUILD_DIR"/}"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

echo "==> Signing the DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

echo "==> Submitting to Apple"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
  echo "notarization failed; the reason is in:" >&2
  echo "  xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}" >&2
  exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Verifying Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo
echo "==> ${DMG}"
echo "    version ${VERSION}"
echo "    sha256  $(shasum -a 256 "$DMG" | awk '{ print $1 }')"
