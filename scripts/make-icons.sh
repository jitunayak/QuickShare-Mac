#!/bin/bash
#
# Regenerates every Quick Share icon from the logo artwork.
#
#     scripts/make-icons.sh
#
# The source is scripts/assets/Quickshare.svg — the official Quick Share logo
# (white arrows on a blue circle). It is public domain, because it consists only
# of simple geometric shapes; see NOTICE.md.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/scripts/assets/Quickshare.svg"
WORK="$ROOT/build/icons"

if [ ! -f "$SVG" ]; then
	echo "error: missing $SVG" >&2
	exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Rasterising $(basename "$SVG")"
# Quick Look is the only SVG renderer that ships with macOS.
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
RENDERED="$WORK/$(basename "$SVG").png"
if [ ! -f "$RENDERED" ]; then
	echo "error: qlmanage did not produce a PNG for $SVG" >&2
	exit 1
fi

echo "==> Generating icons"
swift "$ROOT/scripts/make-icons.swift" \
	"$RENDERED" \
	"$ROOT/QuickShare/Assets.xcassets/AppIcon.appiconset" \
	"$ROOT/QuickShare/Assets.xcassets/MenuBarIcon.imageset"

echo "==> Done"
