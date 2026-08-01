#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ClaudePulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release --arch arm64

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/arm64-apple-macosx/release/ClaudePulse" "$MACOS_DIR/ClaudePulse"
cp "Sources/ClaudePulse/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "Sources/ClaudePulse/Resources/." "$RESOURCES_DIR/"

chmod +x "$MACOS_DIR/ClaudePulse"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
