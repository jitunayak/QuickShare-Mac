# QuickShare for macOS — build and packaging helpers.
#
#   make app        build build/QuickShare.app (Command Line Tools are enough)
#   make run        build, then launch the app
#   make package    build + a distributable .dmg and .zip in build/
#   make icons      regenerate the app/menu bar icons from the logo artwork
#   make xcode      build with Xcode instead (needs Xcode; makes a universal app)
#   make clean      remove build/ and .build/
#
# Override the version for a release:  make package VERSION=1.2.0

VERSION      ?= 1.0.0
BUILD_NUMBER ?= 1

APP := build/QuickShare.app

.PHONY: all app run package icons xcode clean help

all: app

## Build the menu bar app.
app:
	VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) ./scripts/build-app-without-xcode.sh

## Build and launch.
run: app
	open "$(APP)"

## Build a .dmg and .zip ready to upload to a release.
package: app
	VERSION=$(VERSION) ./scripts/package-release.sh

## Regenerate the icons from scripts/assets/Quickshare.svg.
icons:
	./scripts/make-icons.sh

## Build with Xcode (also produces the Finder Share extension).
xcode:
	xcodebuild -project QuickShare.xcodeproj -scheme QuickShare -configuration Release build

## Remove all build products.
clean:
	rm -rf build .build

help:
	@sed -n '2,12p' $(MAKEFILE_LIST) | sed 's/^# \{0,1\}//'
