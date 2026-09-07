#!/bin/bash
# Downloads the pinned Karabiner DriverKit VirtualHIDDevice pkg, verifies its checksum
# and its pqrs signature, and writes it to build/driver.pkg.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

PQRS_TEAM_ID="G43BCU2T37"
PKG_NAME="Karabiner-DriverKit-VirtualHIDDevice-${DRIVER_VERSION}.pkg"
PKG_PATH="${BUILD_DIR}/driver.pkg"

mkdir -p "$BUILD_DIR"

echo "==> Downloading ${DRIVER_PKG_URL}"
curl --fail --location --progress-bar --output "$PKG_PATH" "$DRIVER_PKG_URL"

verify_sha256 "$PKG_PATH" "$PKG_NAME"

echo "==> Checking signature"
SIGNATURE_OUTPUT="$(pkgutil --check-signature "$PKG_PATH")"
echo "$SIGNATURE_OUTPUT"
if [[ "$SIGNATURE_OUTPUT" != *"(${PQRS_TEAM_ID})"* ]]; then
  echo "${PKG_NAME} is not signed by team ${PQRS_TEAM_ID}" >&2
  exit 1
fi

echo "==> ${PKG_PATH} ready"
