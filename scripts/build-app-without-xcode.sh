#!/bin/bash
#
# Build QuickShare.app without Xcode.
#
# The supported build is QuickShare.xcodeproj (see README). This script exists
# for machines that only have the Command Line Tools: it builds the protocol
# core with SwiftPM, compiles the app sources directly, and assembles a
# runnable .app bundle by hand.
#
# It produces an Apple Silicon binary; the Command Line Tools cannot link
# x86_64 Swift at all. Use the Xcode project for a universal build.
#
# What it intentionally leaves out: the Finder Share extension (its UI needs
# the .xib compiler, which ships only with Xcode). Everything else, including
# the app icon, is assembled from the same sources and assets the Xcode project
# uses.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/QuickShare.app"
SDK="$(xcrun --show-sdk-path)"
MIN_MACOS="12.0"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# The Command Line Tools ship their Swift compatibility libraries for arm64
# only, so even a hello-world Swift program will not link for x86_64 here. Use
# Xcode (`make xcode`) if you need a universal binary.
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos${MIN_MACOS}"

echo "==> Building protocol core (QuickShareKit)"
(cd "$ROOT" && swift build)
KIT="$(cd "$ROOT" && swift build --show-bin-path)"

# Stage the bits the app needs in a directory of our own. SwiftPM's build
# directory also holds clang module maps for its C targets (SwiftProtobuf and
# friends), and in some toolchains they sit right where an -I path is searched:
# the Swift compiler then reads them while it builds the bridging header, and
# the build dies with "redefinition of module 'SwiftProtobuf'". The app imports
# QuickShareKit, so all it needs is the Swift modules and the libraries. They
# live in the build directory itself on newer toolchains and in a Modules/
# subdirectory on older ones.
KIT_DIR="$BUILD/kit"
rm -rf "$KIT_DIR"
mkdir -p "$KIT_DIR"
for module in "$KIT"/*.swiftmodule "$KIT"/Modules/*.swiftmodule; do
	if [ -e "$module" ]; then
		cp -R "$module" "$KIT_DIR/"
	fi
done
cp "$KIT"/*.a "$KIT_DIR/"
if [ -z "$(ls -A "$KIT_DIR")" ]; then
	echo "error: found no Swift modules in $KIT" >&2
	exit 1
fi

echo "==> Compiling Objective-C helper"
mkdir -p "$BUILD"
clang -c -fobjc-arc -mmacosx-version-min="$MIN_MACOS" -isysroot "$SDK" \
	-target "$TARGET" \
	"$ROOT/QuickShare/NDNotificationCenterHackery.m" \
	-o "$BUILD/hackery.o"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling and linking QuickShare"
xcrun swiftc \
	-sdk "$SDK" -target "$TARGET" -swift-version 5 \
	-import-objc-header "$ROOT/QuickShare/QuickShare-Bridging-Header.h" \
	-I "$KIT_DIR" -L "$KIT_DIR" \
	-o "$APP/Contents/MacOS/QuickShare" \
	"$ROOT/QuickShare/main.swift" \
	"$ROOT/QuickShare/AppDelegate.swift" \
	"$ROOT/QuickShare/Preferences.swift" \
	"$ROOT/QuickShare/History.swift" \
	"$ROOT/QuickShare/Favourites.swift" \
	"$ROOT/QuickShare/TransferProgress.swift" \
	"$BUILD/hackery.o" \
	-lQuickShareKit

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>QuickShare</string>
	<key>CFBundleIdentifier</key>
	<string>app.quickshare.mac</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>QuickShare</string>
	<key>CFBundleDisplayName</key>
	<string>QuickShare</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSBonjourServices</key>
	<array>
		<string>_FC9F5ED42C8A._tcp</string>
	</array>
	<key>NSLocalNetworkUsageDescription</key>
	<string>QuickShare needs access to your local network to send and receive files.</string>
</dict>
</plist>
PLIST

echo "==> Building app icon"
ICONSET="$BUILD/AppIcon.iconset"
ICON_SRC="$ROOT/QuickShare/Assets.xcassets/AppIcon.appiconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ICON_SRC/16.png"    "$ICONSET/icon_16x16.png"
cp "$ICON_SRC/32.png"    "$ICONSET/icon_16x16@2x.png"
cp "$ICON_SRC/32 1.png"  "$ICONSET/icon_32x32.png"
cp "$ICON_SRC/64.png"    "$ICONSET/icon_32x32@2x.png"
cp "$ICON_SRC/128.png"   "$ICONSET/icon_128x128.png"
cp "$ICON_SRC/256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICON_SRC/256 1.png" "$ICONSET/icon_256x256.png"
cp "$ICON_SRC/512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICON_SRC/512 1.png" "$ICONSET/icon_512x512.png"
cp "$ICON_SRC/1024.png"  "$ICONSET/icon_512x512@2x.png"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

echo "==> Copying resources"
cp "$ROOT/QuickShare/Assets.xcassets/MenuBarIcon.imageset/QuickShare.png"    "$APP/Contents/Resources/MenuBarIcon.png"
cp "$ROOT/QuickShare/Assets.xcassets/MenuBarIcon.imageset/QuickShare@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

echo "==> Signing (ad-hoc, with entitlements)"
codesign --force --sign - --entitlements "$ROOT/QuickShare/QuickShare.entitlements" "$APP"

echo "==> Built $APP"
