#!/usr/bin/env bash
set -e

# ==============================================================================
# Antigravity CLI Notch HUD & Menu Bar Hub - Clean Uninstaller
# ==============================================================================

LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${LAUNCH_AGENTS_DIR}/com.antigravity.notchhud.plist"
GLOBAL_HOOKS_FILE="${HOME}/.gemini/config/hooks.json"

echo ""
echo "🗑️ Antigravity CLI Notch HUD Uninstaller"
echo "=========================================="

# 1. Stop running processes
echo "🛑 Stopping AntigravityBar..."
pkill -f "antigravity-bar" 2>/dev/null || true

# 2. Remove LaunchAgent
if [ -f "$PLIST_FILE" ]; then
    echo "🧹 Removing LaunchAgent auto-start..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
fi

# 3. Remove from Global Hooks
if [ -f "$GLOBAL_HOOKS_FILE" ]; then
    echo "🔌 Removing hook registration from ~/.gemini/config/hooks.json..."
    python3 -c "
import os, json
hooks_file = os.path.expanduser('~/.gemini/config/hooks.json')
if os.path.exists(hooks_file):
    try:
        with open(hooks_file, 'r') as f:
            data = json.load(f)
        if 'mac-notch-hud' in data:
            del data['mac-notch-hud']
            with open(hooks_file, 'w') as f:
                json.dump(data, f, indent=2)
            print('✅ Successfully removed hook entry.')
    except Exception as e:
        print('Warning:', e)
"
fi

echo ""
echo "✅ Uninstallation complete! Antigravity Notch HUD has been removed."
echo ""
