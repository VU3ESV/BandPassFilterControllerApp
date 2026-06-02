#!/usr/bin/env bash
# Creates a distributable DMG with "Band Pass Filter Controller.app" inside and an
# /Applications symlink. Build the app first with ./build-app.sh.
# Usage: VERSION=1.0.0 scripts/make-dmg.sh   ->   dist/BandPassFilterController-<version>-macos.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Band Pass Filter Controller.app"
VERSION="${VERSION:-0.0.0-dev}"
DMG="$DIST/BandPassFilterController-${VERSION}-macos.dmg"

test -d "$APP" || { echo "Build the app first: ./build-app.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging DMG contents at $STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"

echo "==> Creating DMG at $DMG"
hdiutil create \
    -volname "Band Pass Filter Controller ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

ls -lh "$DMG" | awk '{ printf "    %s\n", $0 }'
echo "==> Wrote $DMG"
