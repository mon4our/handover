#!/bin/bash
# Removes the LaunchAgent, app bundle, and CLI. Leaves the config and log in place.
set -euo pipefail

LABELS=("com.github.mon4our.headphone-disconnect" "local.headphone-disconnect")

for label in "${LABELS[@]}"; do
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -rf "$HOME/Applications/Headphone Disconnect.app"
rm -f "$HOME/.local/bin/headphone-disconnect"
pkill -x headphone-disconnect 2>/dev/null || true
echo "Removed. Config kept at ~/.config/headphone-disconnect/config.json"
echo "Log kept at ~/Library/Logs/headphone-disconnect.log"
