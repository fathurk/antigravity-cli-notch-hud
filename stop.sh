#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLIST="$HOME/Library/LaunchAgents/com.antigravity.notchhud.plist"

if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null || true
fi

pkill -f "$DIR/bin/antigravity-bar" 2>/dev/null || true
pkill -f "antigravity-bar" 2>/dev/null || true

echo "AntigravityBar stopped."
