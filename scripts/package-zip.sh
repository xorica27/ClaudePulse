#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ClaudePulse.app"

# shellcheck source=scripts/artifact-slug.sh
source "$ROOT_DIR/scripts/artifact-slug.sh"

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/build-release.sh"
fi

ARCH_SLUG="$(binary_arch_slug "$APP_DIR/Contents/MacOS/ClaudePulse")"
ZIP_PATH="$DIST_DIR/ClaudePulse-macos-$ARCH_SLUG.zip"

rm -f "$ZIP_PATH"
(
  cd "$DIST_DIR"
  /usr/bin/zip -qry -X "$ZIP_PATH" "ClaudePulse.app"
)

echo "Packaged $ZIP_PATH"
