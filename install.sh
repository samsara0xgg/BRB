#!/bin/sh
# Build GuardMode.app, sign it with the Apple Development cert (keeps the camera and Accessibility
# grants across rebuilds), and (re)load the LaunchAgent.
set -e
cd "$(dirname "$0")"
app=build/GuardMode.app
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O -swift-version 5 main.swift GuardApp.swift Sensors.swift Alarm.swift Recorder.swift InputTap.swift Push.swift -o "$app/Contents/MacOS/guard-mode"
codesign -f -s "Apple Development" "$app"
launchctl bootout "gui/$(id -u)/com.allen.guard-mode" 2>/dev/null && sleep 2  # bootout is async
cp com.allen.guard-mode.plist ~/Library/LaunchAgents/
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.allen.guard-mode.plist
echo "loaded; log: ~/Library/Logs/guard-mode.log"
