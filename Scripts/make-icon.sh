#!/bin/bash
# Renders Resources/AppIcon.icns. Run after editing Scripts/make-icon.swift.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

ICONSET="${BUILD_DIR}/AppIcon.iconset"
OUTPUT="${REPO_ROOT}/Resources/AppIcon.icns"

mkdir -p "$BUILD_DIR"
rm -rf "$ICONSET"

echo "==> Rendering icon layers"
swift "${REPO_ROOT}/Scripts/make-icon.swift" "$ICONSET"

echo "==> Building ${OUTPUT#"$REPO_ROOT"/}"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"
rm -rf "$ICONSET"

echo "==> $(ls -lh "$OUTPUT" | awk '{ print $5 }') at ${OUTPUT}"
