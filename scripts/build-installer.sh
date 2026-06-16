#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="悬浮待办"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
IDENTIFIER="com.local.ToDoModule"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/.build/installer-root"
SCRIPTS_DIR="$ROOT_DIR/.build/installer-scripts"
PKG_PATH="$DIST_DIR/$APP_NAME-$VERSION.pkg"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$SCRIPTS_DIR"
mkdir -p "$STAGING_DIR/Applications" "$SCRIPTS_DIR" "$DIST_DIR"
ditto "$ROOT_DIR/.build/$APP_NAME.app" "$STAGING_DIR/Applications/$APP_NAME.app"

cat > "$SCRIPTS_DIR/postinstall" <<'POSTINSTALL'
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="悬浮待办"
APP_BUNDLE_ID="com.local.ToDoModule"
APP_PATH="/Applications/$APP_NAME.app"
CONSOLE_USER="$(stat -f "%Su" /dev/console || true)"

if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
  if ! sudo -u "$CONSOLE_USER" defaults export com.apple.dock - 2>/dev/null | grep -q "$APP_BUNDLE_ID"; then
    sudo -u "$CONSOLE_USER" defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>" || true
    sudo -u "$CONSOLE_USER" killall Dock || true
  fi
  sudo -u "$CONSOLE_USER" open "$APP_PATH" || true
fi

exit 0
POSTINSTALL
chmod +x "$SCRIPTS_DIR/postinstall"

pkgbuild \
  --root "$STAGING_DIR" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_PATH"

echo "$PKG_PATH"
