#!/bin/bash
#
# Build QuickShare.app without Xcode.
#
# The supported build is QuickShare.xcodeproj (see README). This script exists
# for machines that only have the Command Line Tools: it builds the protocol
# core with SwiftPM, compiles the app sources directly, and assembles a
# runnable .app bundle by hand.
#
# What it intentionally leaves out: the Finder Share extension (its UI needs
# the .xib compiler, which ships only with Xcode) and the compiled asset
# catalog (the menu bar icon is installed as a plain PNG instead).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/QuickShare.app"
KIT="$ROOT/.build/out/Products/Debug"
SDK="$(xcrun --show-sdk-path)"
MIN_MACOS="12.0"
TARGET="arm64-apple-macos${MIN_MACOS}"

echo "==> Building protocol core (QuickShareKit)"
(cd "$ROOT" && swift build)

echo "==> Compiling Objective-C helper"
mkdir -p "$BUILD"
clang -c -fobjc-arc -mmacosx-version-min="$MIN_MACOS" -isysroot "$SDK" \
	"$ROOT/QuickShare/NDNotificationCenterHackery.m" \
	-o "$BUILD/hackery.o"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling and linking QuickShare"
xcrun swiftc \
	-sdk "$SDK" -target "$TARGET" -swift-version 5 \
	-import-objc-header "$ROOT/QuickShare/QuickShare-Bridging-Header.h" \
	-I "$KIT" -L "$KIT" \
	-o "$APP/Contents/MacOS/QuickShare" \
	"$ROOT/QuickShare/main.swift" \
	"$ROOT/QuickShare/AppDelegate.swift" \
	"$ROOT/QuickShare/Preferences.swift" \
	"$ROOT/QuickShare/History.swift" \
	"$ROOT/QuickShare/Favourites.swift" \
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
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
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

echo "==> Copying resources"
cp "$ROOT/QuickShare/Assets.xcassets/MenuBarIcon.imageset/QuickShare.png"    "$APP/Contents/Resources/MenuBarIcon.png"
cp "$ROOT/QuickShare/Assets.xcassets/MenuBarIcon.imageset/QuickShare@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

echo "==> Signing (ad-hoc, with entitlements)"
codesign --force --sign - --entitlements "$ROOT/QuickShare/QuickShare.entitlements" "$APP"

echo "==> Built $APP"
