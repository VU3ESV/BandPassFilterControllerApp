#!/bin/bash
# Build BPFExtension.appex and package it as `BPF.radioplugin` -- the installable bundle
# the Amateur Radio Suite browses + installs (zip of plugin.json + the .appex).
#
#   ./scripts/make-radioplugin.sh                  # -> dist/BPF.radioplugin (+ its sha256)
#   VERSION=0.14.0 ./scripts/make-radioplugin.sh   # release: the plugin reports 0.14.0
#
# VERSION (default 0.0.0-dev; a leading "v" is dropped) is stamped into both places the plugin
# reports a version: the .appex Info.plist (MARKETING_VERSION / CURRENT_PROJECT_VERSION) and
# plugin.json's "version" (the __VERSION__ placeholder). The script stops if either is off.
#
# Running the installed plugin needs Developer-ID signing + extension approval; this
# produces an ad-hoc-signed package suitable for the catalog/discovery flow and testing.
set -euo pipefail
cd "$(dirname "$0")/.."

XCODE_DIR="Xcode"
PROJECT="$XCODE_DIR/BandPassFilterControllerPlugin.xcodeproj"
SCHEME="BPFExtension"
DIST="dist"
PKG="$DIST/BPF.radioplugin"
VERSION="${VERSION:-0.0.0-dev}"
VERSION="${VERSION#v}"

# SwiftPM's bare-repo cache trips `safe.bareRepository=explicit` (a common global git
# setting) under xcodebuild; allow it for child git processes without touching config.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

echo "==> Generating Xcode project from project.yml"
( cd "$XCODE_DIR" && xcodegen generate )

echo "==> Building $SCHEME (.appex) -- version $VERSION"
DERIVED="$(mktemp -d)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APPEX="$(/usr/bin/find "$DERIVED/Build/Products" -name 'BPFExtension.appex' -maxdepth 3 | head -1)"
[ -n "$APPEX" ] || { echo "ERROR: BPFExtension.appex not found"; exit 1; }
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPEX/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] || {
  echo "ERROR: .appex reports version '$BUILT_VERSION', expected '$VERSION'"; exit 1; }

echo "==> Assembling $PKG"
STAGE="$(mktemp -d)"
sed "s/__VERSION__/${VERSION}/g" "Xcode/Extension/plugin.json" > "$STAGE/plugin.json"
grep -q "\"version\": \"${VERSION}\"" "$STAGE/plugin.json" || {
  echo "ERROR: plugin.json version was not stamped (is the __VERSION__ placeholder intact?)"; exit 1; }
cp -R "$APPEX" "$STAGE/"

# Only manage our own package -- do NOT wipe $DIST, which in a release pipeline also
# holds the standalone .app built by build-app.sh.
mkdir -p "$DIST"
rm -f "$PKG"
PKG_ABS="$PWD/$PKG"
# plugin.json at the archive ROOT (what PackageInstaller looks for first); --norsrc
# --noextattr keeps the zip clean (no __MACOSX AppleDouble entries that would add a
# second top-level dir and break payload-root detection).
( cd "$STAGE" && ditto -c -k --norsrc --noextattr . "$PKG_ABS" )
rm -rf "$STAGE" "$DERIVED"

SHA="$(shasum -a 256 "$PKG" | awk '{print $1}')"
echo "OK: built $PKG"
echo "    sha256: $SHA"
