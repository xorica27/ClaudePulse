#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ClaudePulse"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Sources/ClaudePulse/Info.plist")"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_NAME="$APP_NAME-macos-arm64.dmg"
DMG_WORK_DIR="$DIST_DIR/dmg-work"
DMG_STAGING_DIR="$DMG_WORK_DIR/staging"
RW_DMG="$DMG_WORK_DIR/$APP_NAME-$VERSION-rw.dmg"
FINAL_DMG="$DIST_DIR/$DMG_NAME"
BACKGROUND_NAME="background.png"

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/build-release.sh"
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required on macOS." >&2
  exit 1
fi

if ! command -v SetFile >/dev/null 2>&1; then
  echo "SetFile is required. Install Xcode Command Line Tools." >&2
  exit 1
fi

while IFS= read -r existing_mount; do
  if [[ -n "$existing_mount" ]]; then
    hdiutil detach "$existing_mount" >/dev/null || true
  fi
done < <(hdiutil info | awk -v volume="/Volumes/$VOLUME_NAME" '$0 ~ volume {print $1}')

rm -rf "$DMG_WORK_DIR"
mkdir -p "$DMG_STAGING_DIR/.background"

cp -R "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
swift "$ROOT_DIR/scripts/generate-dmg-background.swift" "$DMG_STAGING_DIR/.background/$BACKGROUND_NAME"

rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -size 180m \
  "$RW_DMG" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
DEVICE="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {print $1}')"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {for (i=3; i<=NF; i++) {printf "%s%s", (i==3 ? "" : " "), $i}; print ""}')"

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Could not mount DMG for styling." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${DEVICE:-}" ]]; then
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

SetFile -a V "$MOUNT_POINT/.background"

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_POINT" as alias
  tell folder dmgFolder
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set bounds of container window to {140, 140, 820, 560}

    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set background picture of viewOptions to file ".background:$BACKGROUND_NAME"

    set position of item "$APP_NAME.app" of container window to {190, 198}
    set position of item "Applications" of container window to {500, 198}

    update without registering applications
    set bounds of container window to {140, 140, 820, 560}
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync

if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
  echo "DMG styling failed: Finder did not write .DS_Store." >&2
  exit 1
fi

hdiutil detach "$DEVICE" >/dev/null
DEVICE=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

echo "Packaged $FINAL_DMG"
