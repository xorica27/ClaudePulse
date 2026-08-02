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

# Each architecture is built on its own and the slices are merged afterwards.
# Passing several --arch flags to a single `swift build` would be shorter, but
# it routes SwiftPM through xcbuild, which ships only with full Xcode — the
# Command Line Tools alone cannot build that way.
SLICES=()
for arch in $CLAUDEPULSE_ARCHS; do
  echo "Building $arch…"
  swift build -c release --arch "$arch"

  BIN_PATH="$(swift build -c release --arch "$arch" --show-bin-path 2>/dev/null || true)"
  SLICE="$BIN_PATH/ClaudePulse"
  if [[ -z "$BIN_PATH" || ! -f "$SLICE" ]]; then
    SLICE="$ROOT_DIR/.build/$arch-apple-macosx/release/ClaudePulse"
  fi

  if [[ ! -f "$SLICE" ]]; then
    echo "Could not find the $arch build product." >&2
    exit 1
  fi

  SLICES+=("$SLICE")
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# lipo -create takes a single slice happily, so CLAUDEPULSE_ARCHS=arm64 walks
# the same path as a universal build rather than a special case.
/usr/bin/lipo -create "${SLICES[@]}" -output "$MACOS_DIR/ClaudePulse"

for arch in $CLAUDEPULSE_ARCHS; do
  if ! /usr/bin/lipo -archs "$MACOS_DIR/ClaudePulse" | tr ' ' '\n' | grep -qx "$arch"; then
    echo "Merged binary is missing the $arch slice: $(/usr/bin/lipo -archs "$MACOS_DIR/ClaudePulse")" >&2
    exit 1
  fi
done

cp "Sources/ClaudePulse/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "Sources/ClaudePulse/Resources/." "$RESOURCES_DIR/"

chmod +x "$MACOS_DIR/ClaudePulse"

# Signing has to happen after the merge — signing slices first and lipo-ing them
# together afterwards would invalidate the signature.
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR ($(/usr/bin/lipo -archs "$MACOS_DIR/ClaudePulse"))"
