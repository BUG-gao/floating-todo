#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="悬浮待办"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
DIST_DIR="$ROOT_DIR/dist"
DMG_ROOT="$ROOT_DIR/.build/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
TMP_DMG="$DIST_DIR/$APP_NAME-$VERSION.tmp.dmg"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$DMG_ROOT" "$DMG_PATH" "$TMP_DMG"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$ROOT_DIR/.build/$APP_NAME.app" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDRW \
  "$TMP_DMG" >/dev/null

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

rm -f "$TMP_DMG"
echo "$DMG_PATH"
