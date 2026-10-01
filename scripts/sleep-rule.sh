#!/bin/sh
# Installs /etc/sudoers.d/guard-mode, so Guard Mode can run `pmset disablesleep` without a password
# and keep the Mac awake with the lid shut while it guards. Asks for your password once.
set -e
rule=$(mktemp)
trap 'rm -f "$rule"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0\n' "$(id -un)" > "$rule"
sudo visudo -cf "$rule" >/dev/null
sudo install -m 0440 -o root -g wheel "$rule" /etc/sudoers.d/guard-mode
echo "Installed /etc/sudoers.d/guard-mode: guarding keeps the Mac awake with the lid shut."
