#!/bin/sh
# Stops BRB, removes it from login and removes the lid rule. Recordings in ~/Movies/BRB
# and the settings stay; delete this folder to remove the app itself.
cd "$(dirname "$0")"
label=com.allen.guard-mode
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null && echo "Stopped BRB."
rm -f "$HOME/Library/LaunchAgents/$label.plist"
sudo -n pmset -a disablesleep 0 2>/dev/null || true  # in case it stopped mid-guard
if [ -e /etc/sudoers.d/brb ] || [ -e /etc/sudoers.d/guard-mode ]; then
  sudo rm -f /etc/sudoers.d/brb /etc/sudoers.d/guard-mode && echo "Removed the lid rule."
fi
echo "BRB is uninstalled. Recordings stay in ~/Movies/BRB."
