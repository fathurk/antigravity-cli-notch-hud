#!/usr/bin/env bash
set -e

# ==============================================================================
# Antigravity CLI Notch HUD & Menu Bar Hub - Turnkey Automated Installer
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
DISPATCHER_PATH="${SCRIPT_DIR}/dispatcher.py"
GLOBAL_CONFIG_DIR="${HOME}/.gemini/config"
GLOBAL_HOOKS_FILE="${GLOBAL_CONFIG_DIR}/hooks.json"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${LAUNCH_AGENTS_DIR}/com.antigravity.notchhud.plist"

echo ""
echo "🪐⚡ Antigravity CLI Notch HUD & Menu Bar Installer"
echo "======================================================"

# 1. Environment & Prerequisite Checks
echo "🔍 Checking environment..."
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Error: This companion tool requires macOS."
    exit 1
fi

if ! command -v swiftc &>/dev/null; then
    echo "❌ Error: 'swiftc' compiler not found."
    echo "💡 Please install Xcode Command Line Tools by running: xcode-select --install"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "❌ Error: 'python3' is required but not found."
    exit 1
fi

# 2. Compile native binaries
echo "🔨 Compiling native Swift binaries..."
chmod +x "${SCRIPT_DIR}/build.sh"
bash "${SCRIPT_DIR}/build.sh"

# 3. Default Configuration
echo "⚙️ Setting up default configuration..."
if [ ! -f "$CONFIG_FILE" ]; then
    cat << 'DEFAULT_CFG' > "$CONFIG_FILE"
{
  "appearance": {
    "font_size_scale": 1.0,
    "notch_prompt_height": 158,
    "notch_prompt_width": 480,
    "notch_toast_height": 46,
    "notch_toast_width": 380
  },
  "audio": {
    "prompt_sound": "Glass",
    "sound_enabled": true,
    "toast_sound": "Hero"
  },
  "notifications": {
    "approval_timeout_seconds": 15,
    "enable_notch_popup": true,
    "toast_duration_seconds": 3.0
  }
}
DEFAULT_CFG
fi

# 4. Configure Global Antigravity CLI Lifecycle Hooks
echo "🔌 Registering global lifecycle hooks in ~/.gemini/config/hooks.json..."
mkdir -p "$GLOBAL_CONFIG_DIR"

python3 -c "
import os, json

hooks_file = os.path.expanduser('~/.gemini/config/hooks.json')
dispatcher = '${DISPATCHER_PATH}'

existing = {}
if os.path.exists(hooks_file):
    try:
        with open(hooks_file, 'r') as f:
            existing = json.load(f)
    except Exception:
        existing = {}

existing['mac-notch-hud'] = {
    'enabled': True,
    'PreToolUse': [
        {
            'matcher': '*',
            'hooks': [
                {
                    'type': 'command',
                    'command': f'python3 {dispatcher}',
                    'timeout': 600
                }
            ]
        }
    ],
    'Stop': [
        {
            'type': 'command',
            'command': f'python3 {dispatcher} --stop-hook',
            'timeout': 10
        }
    ]
}

with open(hooks_file, 'w') as f:
    json.dump(existing, f, indent=2)
"

# 5. Set up macOS LaunchAgent for Auto-Start on Login
echo "🚀 Setting up automatic launch on login (LaunchAgent)..."
mkdir -p "$LAUNCH_AGENTS_DIR"

# Stop existing instance if running
pkill -f "${BIN_DIR}/antigravity-bar" 2>/dev/null || true

cat << EOF_PLIST > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.antigravity.notchhud</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN_DIR}/antigravity-bar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/antigravity-bar.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/antigravity-bar.err</string>
</dict>
</plist>
EOF_PLIST

# Load LaunchAgent
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE" 2>/dev/null || true

# 6. Start Menu Bar App Now
nohup "${BIN_DIR}/antigravity-bar" > /dev/null 2>&1 &

echo ""
echo "🎉 Installation Complete!"
echo "======================================================"
echo "⚡ AntigravityBar is running in your top macOS menu bar!"
echo "📱 Top Notch HUD alerts are now active for ALL conversations."
echo "🔄 Auto-start enabled: launches automatically on Mac login."
echo ""
echo "💡 To configure settings, click '⚡ AGY' in your top menu bar."
echo "💡 To uninstall anytime, run: ./uninstall.sh"
echo ""
