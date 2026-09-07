#!/bin/bash
# Downloads the pinned kanata arm64 release, verifies its checksum, and extracts the
# cmd-disabled binary to build/kanata.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

ZIP_NAME="macos-binaries-arm64.zip"
ZIP_URL="https://github.com/jtroo/kanata/releases/download/v${KANATA_VERSION}/${ZIP_NAME}"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"
KANATA_PATH="${BUILD_DIR}/kanata"

mkdir -p "$BUILD_DIR"

echo "==> Downloading ${ZIP_URL}"
curl --fail --location --progress-bar --output "$ZIP_PATH" "$ZIP_URL"

verify_sha256 "$ZIP_PATH" "$ZIP_NAME"

echo "==> Extracting kanata_macos_arm64"
UNZIP_DIR="$(mktemp -d)"
trap 'rm -rf "$UNZIP_DIR"' EXIT
unzip -q -o "$ZIP_PATH" -d "$UNZIP_DIR"
if [[ ! -f "${UNZIP_DIR}/kanata_macos_arm64" ]]; then
  echo "kanata_macos_arm64 not found in ${ZIP_NAME}" >&2
  exit 1
fi
cp "${UNZIP_DIR}/kanata_macos_arm64" "$KANATA_PATH"
chmod +x "$KANATA_PATH"
xattr -c "$KANATA_PATH" 2>/dev/null || true

echo "==> Checking architecture"
file "$KANATA_PATH"
if ! file "$KANATA_PATH" | grep -q 'arm64'; then
  echo "${KANATA_PATH} is not arm64" >&2
  exit 1
fi

echo "==> Checking version"
VERSION_OUTPUT="$("$KANATA_PATH" --version)"
echo "$VERSION_OUTPUT"
if [[ "$VERSION_OUTPUT" != *"$KANATA_VERSION"* ]]; then
  echo "expected version ${KANATA_VERSION}, got: ${VERSION_OUTPUT}" >&2
  exit 1
fi

echo "==> Checking that cmd is disabled"
CMD_CONFIG="${UNZIP_DIR}/cmd-probe.kbd"
cat > "$CMD_CONFIG" <<'EOF'
(defcfg process-unmapped-keys no)
(defsrc a)
(deflayer base (cmd echo barnata))
EOF
CHECK_OUTPUT="$("$KANATA_PATH" --cfg "$CMD_CONFIG" --check 2>&1 || true)"
if [[ "$CHECK_OUTPUT" != *"compiled to never allow cmd"* ]]; then
  echo "cmd is not disabled in this binary; --check said:" >&2
  echo "$CHECK_OUTPUT" >&2
  exit 1
fi

echo "==> ${KANATA_PATH} ready"
