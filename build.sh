#!/bin/sh
# Builds build/BRB.app (Apple Silicon, macOS 14 or later). Signs it with your Apple Development
# certificate when there is one, which keeps the camera and Accessibility grants across rebuilds;
# otherwise ad hoc (macOS then asks for those again after each rebuild). SIGN_IDENTITY overrides.
set -e
cd "$(dirname "$0")"
app=build/BRB.app
rm -rf "$app" build/GuardMode.app  # and the build from before the rename
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 ./*.swift -o "$app/Contents/MacOS/brb"
identity=${SIGN_IDENTITY:-}
if [ -z "$identity" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    identity="Apple Development"
  else
    identity=-
  fi
fi
# SIGN_FLAGS: extra codesign flags, such as the hardened runtime scripts/release.sh asks for.
codesign -f -s "$identity" --entitlements BRB.entitlements ${SIGN_FLAGS:-} "$app"
[ "$identity" = - ] && echo "signed ad hoc (no Apple Development certificate found)"
echo "built $app"
