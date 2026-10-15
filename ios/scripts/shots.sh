#!/bin/bash
# Screenshots of the demo scenes in the iOS simulator, for checking the screens against the prototype.
#   ios/scripts/shots.sh path/to/BRB.app out-dir [path/to/BRBGallery.app]
# The app is launched in demo mode (see LaunchOptions.swift): no Mac, no relay, no permission prompts.
set -u
APP="$1"
OUT="$2"
GALLERY="${3:-}"
mkdir -p "$OUT"
BUNDLE=com.allen.brb

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in d.items():
    for x in devs:
        if x["name"] == "iPhone 17 Pro":
            best = x["udid"]
print(best)')
echo "simulator $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl install "$UDID" "$APP"

shot() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" $BUNDLE >/dev/null 2>&1
  xcrun simctl launch "$UDID" $BUNDLE -demo 1 "$@" >/dev/null || { echo "launch failed: $name"; return; }
  sleep 4
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 || echo "shot failed: $name"
  echo "shot $name"
}

# English
shot devices-idle -scene idle
shot devices-armed -scene armed
shot devices-partial -scene partial
shot devices-siren -scene siren
shot devices-offline -scene offline
shot devices-empty -scene empty
shot devices-loading -scene idle -pstate loading
shot devices-error -scene idle -pstate error
shot mac-idle -scene idle -open mac
shot mac-armed -scene armed -open mac
shot mac-siren -scene siren -open mac
shot mac-offline -scene offline -open mac
shot start -scene idle -open start
shot alarm-warn -scene warn -open alarm
shot alarm-siren -scene siren -open alarm
shot alarm-muted -scene muted -open alarm
shot alarm-back -scene back -open alarm
shot alarm-done -scene done -open alarm
shot alarm-offline -scene offlineAlarm -open alarm
shot records -scene done -open records
shot record -scene done -open record
shot evidence -scene done -open evidence
shot share -scene done -open share
shot settings -scene armed -open settings
shot privacy -scene armed -open privacy
shot faq -scene armed -open faq
shot paywall -scene idle -open paywall
shot onb-welcome -scene empty -onb welcome
shot onb-notif -scene empty -onb notif
shot onb-crit -scene empty -onb crit
shot onb-scan -scene empty -onb scan
shot onb-code -scene empty -onb code
shot onb-paired -scene empty -onb paired
shot onb-camdenied -scene empty -onb camdenied
shot onb-notifoff -scene idle -onb notifoff -notifOff 1

# Chinese
ZH=(-AppleLanguages "(zh-Hans)" -AppleLocale zh_CN)
shot zh-devices-armed -scene armed "${ZH[@]}"
shot zh-mac-armed -scene armed -open mac "${ZH[@]}"
shot zh-start -scene idle -open start "${ZH[@]}"
shot zh-alarm-siren -scene siren -open alarm "${ZH[@]}"
shot zh-alarm-done -scene done -open alarm "${ZH[@]}"
shot zh-records -scene done -open records "${ZH[@]}"
shot zh-settings -scene armed -open settings "${ZH[@]}"
shot zh-paywall -scene idle -open paywall "${ZH[@]}"
shot zh-onb-welcome -scene empty -onb welcome "${ZH[@]}"

# The widgets, the Live Activity and the Dynamic Island, drawn by the gallery app.
if [ -n "$GALLERY" ]; then
  xcrun simctl install "$UDID" "$GALLERY"
  gshot() {
    local name="$1"
    shift
    xcrun simctl terminate "$UDID" com.allen.brb.gallery >/dev/null 2>&1
    xcrun simctl launch "$UDID" com.allen.brb.gallery -page "$name" "$@" >/dev/null || { echo "launch failed: $name"; return; }
    sleep 3
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/w-$name.png" >/dev/null 2>&1 || echo "shot failed: $name"
    echo "shot w-$name"
  }
  for page in home1 home2 home3 lock live1 live2 island1 island2 island3; do gshot "$page"; done
  gshot home1 -AppleLanguages "(zh-Hans)" -AppleLocale zh_CN
  mv "$OUT/w-home1.png" "$OUT/w-zh-home1.png" 2>/dev/null
  gshot live1 -AppleLanguages "(zh-Hans)" -AppleLocale zh_CN
  mv "$OUT/w-live1.png" "$OUT/w-zh-live1.png" 2>/dev/null
  gshot home1 -dark 0
  mv "$OUT/w-home1.png" "$OUT/w-light-home1.png" 2>/dev/null
fi

# Smaller JPEGs, so a few dozen fit in a branch.
for f in "$OUT"/*.png; do
  sips -s format jpeg -s formatOptions 82 -Z 1000 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 && rm "$f"
done
ls -la "$OUT" | head -80
