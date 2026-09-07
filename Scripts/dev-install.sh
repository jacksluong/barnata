#!/bin/bash
# Replaces /Applications/Barnata.app with the local build and launches it.
set -euo pipefail

source "$(dirname "$0")/vars.sh"

APP="${BUILD_DIR}/${APP_NAME}.app"
INSTALLED="/Applications/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "${APP} does not exist, run build-app.sh --debug first" >&2; exit 1; }

echo "==> Quitting the running app"
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Copying to ${INSTALLED}"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"

echo "==> Launching"
open "$INSTALLED"

echo "==> Daemon status"
launchctl print "system/${DAEMON_LABEL}" 2>/dev/null | head -20 \
  || echo "not registered yet, approve it from the app's Setup menu"
