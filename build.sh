#!/bin/sh
# Builds build/GuardMode.app (Apple Silicon, macOS 14 or later). Signs it with the Apple Development
# certificate, which keeps the camera and Accessibility grants across rebuilds; SIGN_IDENTITY=- signs
# ad hoc instead (CI).
set -e
cd "$(dirname "$0")"
app=build/GuardMode.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 ./*.swift -o "$app/Contents/MacOS/guard-mode"
codesign -f -s "${SIGN_IDENTITY:-Apple Development}" "$app"
echo "built $app"
