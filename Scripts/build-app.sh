#!/bin/bash
# Assembles build/Barnata.app from the SwiftPM products and signs it.
# --debug builds the debug configuration and signs without a secure timestamp.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

CONFIGURATION=release
SIGN_ARGS=()
if [[ "${1:-}" == "--debug" ]]; then
  CONFIGURATION=debug
  SIGN_ARGS=(--debug)
fi

APP="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP}/Contents"

# Version from git: CFBundleVersion must increase on every build for the app's update flow
SHORT_VERSION="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo 0.1.0)"
SHORT_VERSION="${SHORT_VERSION#v}"
BUNDLE_VERSION="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
[[ "$CONFIGURATION" == "debug" ]] && BUNDLE_VERSION="${BUNDLE_VERSION}.$(date +%H%M%S)"

echo "==> Fetching bundled binaries"
[[ -f "${BUILD_DIR}/kanata" ]] || "${REPO_ROOT}/Scripts/fetch-kanata.sh"
[[ -f "${BUILD_DIR}/driver.pkg" ]] || "${REPO_ROOT}/Scripts/fetch-driver.sh"

echo "==> Building ${CONFIGURATION} (arm64)"
(cd "$REPO_ROOT" && swift build -c "$CONFIGURATION" --arch arm64)
PRODUCTS="$(cd "$REPO_ROOT" && swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources" "${CONTENTS}/Library/LaunchDaemons"

cp "${PRODUCTS}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "${PRODUCTS}/barnata-daemon" "${CONTENTS}/MacOS/barnata-daemon"
cp "${BUILD_DIR}/kanata" "${CONTENTS}/MacOS/kanata"

sed -e "s/__BUNDLE_VERSION__/${BUNDLE_VERSION}/" -e "s/__SHORT_VERSION__/${SHORT_VERSION}/" \
  "${REPO_ROOT}/Resources/Info-App.plist" > "${CONTENTS}/Info.plist"
cp "${REPO_ROOT}/Resources/daemon.plist" "${CONTENTS}/Library/LaunchDaemons/${DAEMON_LABEL}.plist"

DRIVER_PKG_NAME="Karabiner-DriverKit-VirtualHIDDevice-${DRIVER_VERSION}.pkg"
cp "${BUILD_DIR}/driver.pkg" "${CONTENTS}/Resources/${DRIVER_PKG_NAME}"
cat > "${CONTENTS}/Resources/driver-requirements.json" <<EOF
{
  "requiredVersion": "${DRIVER_VERSION}",
  "packageName": "${DRIVER_PKG_NAME}"
}
EOF

if [[ -d "${REPO_ROOT}/Resources/status-icons" ]]; then
  cp -R "${REPO_ROOT}/Resources/status-icons" "${CONTENTS}/Resources/status-icons"
fi

"${REPO_ROOT}/Scripts/sign.sh" "${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}"

echo "==> ${APP} version ${SHORT_VERSION} (${BUNDLE_VERSION})"
