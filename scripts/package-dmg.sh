#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ClaudePulse"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Sources/ClaudePulse/Info.plist")"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_WORK_DIR="$DIST_DIR/dmg-work"
DMG_STAGING_DIR="$DMG_WORK_DIR/staging"
RW_DMG="$DMG_WORK_DIR/$APP_NAME-$VERSION-rw.dmg"
BACKGROUND_NAME="background.png"

# shellcheck source=scripts/artifact-slug.sh
source "$ROOT_DIR/scripts/artifact-slug.sh"

# Single source of truth for the installer window: the background is rendered at
# exactly these dimensions, so the two can never drift apart.
WINDOW_X=140
WINDOW_Y=140
WINDOW_WIDTH=680
WINDOW_HEIGHT=420
ICON_SIZE=112
ICON_Y=198
APP_ICON_X=190
LINK_ICON_X=500

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/build-release.sh"
fi

ARCH_SLUG="$(binary_arch_slug "$APP_DIR/Contents/MacOS/$APP_NAME")"
FINAL_DMG="$DIST_DIR/$APP_NAME-macos-$ARCH_SLUG.dmg"

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
swift "$ROOT_DIR/scripts/generate-dmg-background.swift" \
  "$DMG_STAGING_DIR/.background/$BACKGROUND_NAME" \
  "$WINDOW_WIDTH" "$WINDOW_HEIGHT"

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

# Finder routinely ignores the first `set bounds` while it is still laying the
# window out, leaving a window wider than the background and a blank band down
# the right-hand side. Set it repeatedly until it takes, then report back what
# actually stuck so the build can refuse to ship a misaligned window.
ACTUAL_BOUNDS="$(osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_POINT" as alias
  tell folder dmgFolder
    open
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false

    set viewOptions to icon view options of theWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set background picture of viewOptions to file ".background:$BACKGROUND_NAME"

    set position of item "$APP_NAME.app" of theWindow to {$APP_ICON_X, $ICON_Y}
    set position of item "Applications" of theWindow to {$LINK_ICON_X, $ICON_Y}

    repeat 10 times
      set bounds of theWindow to {$WINDOW_X, $WINDOW_Y, $WINDOW_X + $WINDOW_WIDTH, $WINDOW_Y + $WINDOW_HEIGHT}
      delay 0.4
      set b to bounds of theWindow
      if ((item 3 of b) - (item 1 of b)) is $WINDOW_WIDTH and ((item 4 of b) - (item 2 of b)) is $WINDOW_HEIGHT then
        exit repeat
      end if
    end repeat

    update without registering applications
    delay 1
    set b to bounds of theWindow
    close
  end tell
  return (((item 3 of b) - (item 1 of b)) as text) & "x" & (((item 4 of b) - (item 2 of b)) as text)
end tell
APPLESCRIPT
)"

sync

if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
  echo "DMG styling failed: Finder did not write .DS_Store." >&2
  exit 1
fi

if [[ "$ACTUAL_BOUNDS" != "${WINDOW_WIDTH}x${WINDOW_HEIGHT}" ]]; then
  echo "DMG styling failed: Finder settled on a ${ACTUAL_BOUNDS} window, expected ${WINDOW_WIDTH}x${WINDOW_HEIGHT}." >&2
  echo "The ${WINDOW_WIDTH}x${WINDOW_HEIGHT} background would not fill it." >&2
  exit 1
fi

hdiutil detach "$DEVICE" >/dev/null
DEVICE=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

echo "Packaged $FINAL_DMG"
