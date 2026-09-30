#!/bin/sh
# Build GuardMode.app (build.sh) and (re)load the LaunchAgent.
set -e
cd "$(dirname "$0")"
./build.sh
launchctl bootout "gui/$(id -u)/com.allen.guard-mode" 2>/dev/null && sleep 2  # bootout is async
cp com.allen.guard-mode.plist ~/Library/LaunchAgents/
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.allen.guard-mode.plist
echo "loaded; log: ~/Library/Logs/guard-mode.log"
