#!/bin/bash
#
# Package build/QuickShare.app into the two artifacts attached to a GitHub
# release: a compressed disk image (.dmg) and a zip.
#
# Run it through `make package`, or directly:
#
#     VERSION=1.0.0 ./scripts/package-release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
APP="$ROOT/build/QuickShare.app"
NAME="QuickShare-${VERSION}"
ZIP="$ROOT/build/$NAME.zip"
DMG="$ROOT/build/$NAME.dmg"
STAGE="$ROOT/build/dmg-staging"

if [ ! -d "$APP" ]; then
	echo "error: $APP does not exist — run 'make app' (or 'make universal') first." >&2
	exit 1
fi

echo "==> Zipping $NAME.zip"
rm -f "$ZIP"
# ditto keeps the bundle's symlinks, resource forks and permissions intact,
# which the plain `zip` tool does not.
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building $NAME.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# Drag-to-install target shown next to the app in the mounted volume.
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "QuickShare $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Artifacts"
ls -lh "$ZIP" "$DMG"
shasum -a 256 "$ZIP" "$DMG"
