#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ClaudePulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Release builds are universal so one download runs natively on both Apple
# Silicon and Intel Macs. Override for a single-slice local build, e.g.
# CLAUDEPULSE_ARCHS=arm64 scripts/build-release.sh
CLAUDEPULSE_ARCHS="${CLAUDEPULSE_ARCHS:-arm64 x86_64}"

cd "$ROOT_DIR"

ARCH_FLAGS=()
for arch in $CLAUDEPULSE_ARCHS; do
  ARCH_FLAGS+=("--arch" "$arch")
done

swift build -c release "${ARCH_FLAGS[@]}"

# A multi-arch build lands in .build/apple/Products/Release rather than the
# single-arch triple directory, so ask SwiftPM where it put things instead of
# guessing.
BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/ClaudePulse"

if [[ ! -f "$BINARY" ]]; then
  echo "Expected the built binary at $BINARY." >&2
  exit 1
fi

for arch in $CLAUDEPULSE_ARCHS; do
  if ! /usr/bin/lipo -archs "$BINARY" | tr ' ' '\n' | grep -qx "$arch"; then
    echo "Built binary is missing the $arch slice: $(/usr/bin/lipo -archs "$BINARY")" >&2
    exit 1
  fi
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/ClaudePulse"
cp "Sources/ClaudePulse/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "Sources/ClaudePulse/Resources/." "$RESOURCES_DIR/"

chmod +x "$MACOS_DIR/ClaudePulse"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR ($(/usr/bin/lipo -archs "$MACOS_DIR/ClaudePulse"))"
