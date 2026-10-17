#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLIST="$HOME/Library/LaunchAgents/com.antigravity.notchhud.plist"

# 1. Stop any existing process
pkill -f "$DIR/bin/antigravity-bar" 2>/dev/null || true
pkill -f "antigravity-bar" 2>/dev/null || true

# 2. Start via LaunchAgent if installed, or fallback to robust detached process
if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl kickstart -kp "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null || true
else
    ( "$DIR/bin/antigravity-bar" </dev/null >/dev/null 2>&1 & )
fi

# 3. Wait briefly and verify running
sleep 0.5
if pgrep -f "antigravity-bar" >/dev/null 2>&1; then
    echo "⚡ AntigravityBar is running in your top macOS menu bar!"
else
    echo "⚠️ Verifying AntigravityBar with launchctl..."
    launchctl print "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null | grep -E "state|pid" || true
fi
