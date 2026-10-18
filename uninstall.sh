#!/bin/sh
# Stops Back in 5, removes it from login and removes the lid rule. Recordings in "~/Movies/Back in 5"
# and the settings stay; delete this folder to remove the app itself.
cd "$(dirname "$0")"
label=com.allen.guard-mode
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null && echo "Stopped Back in 5."
rm -f "$HOME/Library/LaunchAgents/$label.plist"
sudo -n pmset -a disablesleep 0 2>/dev/null || true  # in case it stopped mid-guard
if [ -e /etc/sudoers.d/brb ] || [ -e /etc/sudoers.d/guard-mode ]; then
  sudo rm -f /etc/sudoers.d/brb /etc/sudoers.d/guard-mode && echo "Removed the lid rule."
fi
echo "Back in 5 is uninstalled. Recordings stay in ~/Movies/Back in 5."
