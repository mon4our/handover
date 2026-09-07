#!/bin/bash
# Removes the LaunchAgent, app bundle, and CLI. Leaves the config and log in place.
set -euo pipefail

LABELS=("com.github.mon4our.handover" "com.github.mon4our.headphone-disconnect" "local.headphone-disconnect")

for label in "${LABELS[@]}"; do
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -rf "$HOME/Applications/Handover.app" "$HOME/Applications/Headphone Disconnect.app"
rm -f "$HOME/.local/bin/handover" "$HOME/.local/bin/headphone-disconnect"
pkill -x handover 2>/dev/null || true
echo "Removed. Config kept at ~/.config/handover/config.json"
echo "Log kept at ~/Library/Logs/handover.log"
