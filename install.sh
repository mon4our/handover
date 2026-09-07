#!/bin/bash
# Builds Handover, writes a config if there isn't one, and loads the LaunchAgent
# that starts the menu bar app at login.
# usage: ./install.sh [device-address ...]
set -euo pipefail

cd "$(dirname "$0")"

LABEL="com.github.mon4our.handover"
# Labels used by earlier versions, booted out on upgrade.
OLD_LABELS=("com.github.mon4our.headphone-disconnect" "local.headphone-disconnect")
APP="$HOME/Applications/Handover.app"
BIN_DIR="$HOME/.local/bin"
CLI="$BIN_DIR/handover"
CONFIG_DIR="$HOME/.config/handover"
CONFIG="$CONFIG_DIR/config.json"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/handover.log"

echo "==> building"
./build.sh

echo "==> stopping any running copy"
for label in "$LABEL" "${OLD_LABELS[@]}"; do
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
pkill -x handover 2>/dev/null || true

echo "==> installing $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
install -m 755 handover "$APP/Contents/MacOS/handover"
mkdir -p "$APP/Contents/Resources"
install -m 644 Resources/Info.plist "$APP/Contents/Info.plist"
install -m 644 Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature keeps macOS from re-prompting for Bluetooth/Accessibility after each rebuild.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "    (codesign skipped)"
# Nudge Finder to pick up the icon instead of showing a stale generic one.
touch "$APP"

echo "==> installing CLI to $CLI"
mkdir -p "$BIN_DIR"
install -m 755 handover "$CLI"

mkdir -p "$CONFIG_DIR"
# This used to be called headphone-disconnect; keep the device choice across the rename.
OLD_CONFIG="$HOME/.config/headphone-disconnect/config.json"
if [ ! -f "$CONFIG" ] && [ -f "$OLD_CONFIG" ]; then
    echo "==> migrating config from headphone-disconnect"
    cp "$OLD_CONFIG" "$CONFIG"
fi
if [ "$#" -gt 0 ]; then
    devices=("$@")
elif [ -f "$CONFIG" ]; then
    echo "==> keeping existing $CONFIG"
    devices=()
else
    # Default to whatever audio device is connected right now — usually the headphones
    # you are wearing while installing this. You can change this in the menu later.
    devices=()
    while IFS= read -r addr; do
        devices+=("$addr")
    done < <("$CLI" status 2>/dev/null |
        awk '/^All paired audio devices:/ {section=1; next}
             section && /connected$/ {gsub(/-/, ":", $1); print toupper($1)}')
    if [ "${#devices[@]}" -eq 0 ]; then
        echo "    no audio device connected; pick one from the menu bar after install"
    fi
fi

if [ "${#devices[@]}" -gt 0 ]; then
    echo "==> writing $CONFIG for: ${devices[*]}"
    {
        printf '{\n  "devices": [\n'
        for i in "${!devices[@]}"; do
            sep=","; [ "$i" -eq $(( ${#devices[@]} - 1 )) ] && sep=""
            printf '    "%s"%s\n' "${devices[$i]}" "$sep"
        done
        printf '  ],\n'
        printf '  "enabled": true,\n'
        printf '  "reconnectOnWake": true,\n'
        printf '  "reconnectDelay": 3,\n'
        printf '  "reconnectAttempts": 6,\n'
        printf '  "reconnectInterval": 4,\n'
        printf '  "skipDarkWake": true,\n'
        printf '  "darkWakeGraceSeconds": 120\n'
        printf '}\n'
    } > "$CONFIG"
elif [ ! -f "$CONFIG" ]; then
    printf '{\n  "devices": []\n}\n' > "$CONFIG"
fi

echo "==> writing $PLIST"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/handover</string>
        <string>menubar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- Restart on crash, but respect Quit from the menu. -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST_EOF

echo "==> loading the agent"
launchctl bootstrap "gui/$UID" "$PLIST"
sleep 2
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    echo "    running — look for the headphones icon in your menu bar"
else
    echo "    failed to start; see $LOG" >&2
    exit 1
fi

echo
echo "Log: $LOG"
tail -n 3 "$LOG" 2>/dev/null || true
