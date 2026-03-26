#!/bin/bash
set -e

APP_NAME="OpenTextGrabber"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile
swiftc \
    -swift-version 5 \
    -O \
    -target arm64-apple-macosx14.0 \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework Vision \
    -framework Carbon \
    -framework ScreenCaptureKit \
    Sources/*.swift

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"
cp assets/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"

# Ad-hoc code sign
codesign --force --sign - "$APP_BUNDLE"

echo "Done! Built at: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "Hotkey:  Cmd+Shift+2 (configurable)"
