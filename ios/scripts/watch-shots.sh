#!/bin/bash
# Screenshots of the Apple Watch app's demo scenes (see `loadDemo` in Watch/WatchModel.swift).
#   ios/scripts/watch-shots.sh path/to/BRBWatch.app out-dir
set -u
APP="$1"
OUT="$2"
mkdir -p "$OUT"
BUNDLE=com.allen.brb.watchkitapp

UDID=$(python3 - <<'PY'
import json, subprocess
def sim(*a):
    return json.loads(subprocess.check_output(["xcrun", "simctl", *a, "-j"]))
devices = sim("list", "devices", "available")["devices"]
best = None
for runtime, devs in devices.items():
    if "watchOS" not in runtime:
        continue
    for d in devs:
        if "Apple Watch" in d["name"] and ("Series 11" in d["name"] or best is None):
            best = d["udid"]
if best is None:
    runtimes = [r for r in sim("list", "runtimes")["runtimes"] if "watchOS" in r["name"] and r.get("isAvailable")]
    types = [t for t in sim("list", "devicetypes")["devicetypes"] if "Apple Watch Series" in t["name"]]
    if runtimes and types:
        best = subprocess.check_output(
            ["xcrun", "simctl", "create", "brb-watch", types[-1]["identifier"], runtimes[-1]["identifier"]]
        ).decode().strip()
print(best)
PY
)
echo "watch simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || { echo "install failed"; exit 1; }

shot() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" $BUNDLE >/dev/null 2>&1
  xcrun simctl launch "$UDID" $BUNDLE "$@" >/dev/null || { echo "launch failed: $name"; return; }
  sleep 4
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 || echo "shot failed: $name"
  echo "shot $name"
}

for scene in idle armed arming warn siren offline done many nopro empty; do
  shot "$scene" -wdemo "$scene"
done
ZH=(-AppleLanguages "(zh-Hans)" -AppleLocale zh_CN)
for scene in idle armed siren; do
  shot "zh-$scene" -wdemo "$scene" "${ZH[@]}"
done
ls -la "$OUT"
