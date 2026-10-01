#!/bin/sh
# Builds Guard Mode, starts it at login (restarted after a crash or a kill), and offers to install
# the rule that keeps the Mac awake with the lid shut. Run it again after pulling changes.
set -e
cd "$(dirname "$0")"
repo=$(pwd)
label=com.allen.guard-mode

fail() { echo "$1" >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || fail "Guard Mode needs a Mac with Apple silicon."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Guard Mode needs macOS 14 or later."
xcode-select -p >/dev/null 2>&1 || fail "First install Apple's command line tools: xcode-select --install
Then run ./install.sh again."

echo "Building…"
./build.sh

agents="$HOME/Library/LaunchAgents"
mkdir -p "$agents" "$HOME/Library/Logs"
sed -e "s|__PROGRAM__|$repo/build/GuardMode.app/Contents/MacOS/guard-mode|" \
    -e "s|__LOG__|$HOME/Library/Logs/guard-mode.log|g" "$label.plist" > "$agents/$label.plist"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null && sleep 2  # bootout is async
launchctl bootstrap "gui/$(id -u)" "$agents/$label.plist"
echo "Guard Mode is running: the shield in the menu bar. Log: ~/Library/Logs/guard-mode.log"

if sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  echo "The lid rule is already installed."
elif [ -t 0 ]; then
  printf "Install the rule that keeps the Mac awake with the lid shut? It asks for your password once. [Y/n] "
  read -r answer
  case "$answer" in
    [Nn]*) echo "Skipped. The panel can copy the command for later: ./scripts/sleep-rule.sh" ;;
    *) ./scripts/sleep-rule.sh ;;
  esac
else
  echo "To keep the Mac awake with the lid shut, run once: ./scripts/sleep-rule.sh"
fi
