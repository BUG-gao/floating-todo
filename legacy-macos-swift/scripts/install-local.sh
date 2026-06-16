#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="悬浮待办"
APP_BUNDLE_ID="com.local.ToDoModule"
APP_PATH="/Applications/$APP_NAME.app"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null
rm -rf "$APP_PATH"
ditto "$ROOT_DIR/.build/$APP_NAME.app" "$APP_PATH"

if ! defaults export com.apple.dock - 2>/dev/null | grep -q "$APP_BUNDLE_ID"; then
  defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock || true
fi

open "$APP_PATH"
echo "$APP_PATH"
