#!/bin/bash
# Makes dist/BRB.dmg, the download in the README: BRB signed with your Developer ID and the
# hardened runtime, notarized and stapled, in a disk image that is signed, notarized and stapled
# too, then published as the GitHub release for the version in Info.plist.
#
# Needs, once per Mac: a "Developer ID Application" certificate in the login keychain, a
# notarytool keychain profile (NOTARY_PROFILE, default Typlus) and the GitHub CLI signed in.
# The disk image's window (background, icon places) comes from dmgbuild, installed into build/venv.
# LOCAL=1 builds the disk image ad hoc and stops there (CI does this).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
NOTARY_PROFILE=${NOTARY_PROFILE:-Typlus}
LOCAL=${LOCAL:-0}
app=build/BRB.app
dmg=dist/BRB.dmg

if [ "$LOCAL" = 1 ]; then
  identity=-
else
  [ -z "$(git status --porcelain)" ] || { echo "Commit first: a release is built from a clean tree." >&2; exit 1; }
  identity=${IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
  [ -n "$identity" ] || { echo "No Developer ID Application certificate in the keychain." >&2; exit 1; }
  command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh, then gh auth login." >&2; exit 1; }
fi

notarize() {
  # grep without -q: -q stops at the first match, tee dies of SIGPIPE and pipefail fails an accepted submission.
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee /dev/stderr | grep 'status: Accepted' > /dev/null
}

SIGN_IDENTITY="$identity" SIGN_FLAGS="$([ "$LOCAL" = 1 ] || echo --options runtime --timestamp)" ./build.sh
mkdir -p dist
if [ "$LOCAL" != 1 ]; then
  # The app gets its own ticket, so the copy dragged out of the disk image opens offline.
  ditto -c -k --keepParent "$app" dist/BRB.zip
  notarize dist/BRB.zip
  xcrun stapler staple "$app"
  spctl -a -vv "$app"
fi

# A window that opens on BRB, an arrow and Applications, saying to drag one onto the other.
rm -f "$dmg" build/dmg-background*
"$app/Contents/MacOS/brb" dmg-background build/dmg-background
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out build/dmg-background.tiff 2> /dev/null
[ -x build/venv/bin/dmgbuild ] || { python3 -m venv build/venv && build/venv/bin/pip install -q "dmgbuild>=1.6,<2"; }
build/venv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$app" -D background=build/dmg-background.tiff BRB "$dmg" > /dev/null
if [ "$LOCAL" = 1 ]; then
  echo "made $dmg (ad hoc, not notarized)"
  exit 0
fi
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

# The asset keeps the name BRB.dmg, so releases/latest/download/BRB.dmg always points at the newest.
gh release create "v$VERSION" "$dmg" --title "BRB $VERSION" \
  --notes "Download BRB.dmg, open it and drag BRB into Applications. Apple silicon, macOS 14 or later."
echo "published BRB $VERSION: https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg"
