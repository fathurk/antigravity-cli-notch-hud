#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Kill existing instance if any
pkill -f "$DIR/bin/antigravity-bar" 2>/dev/null || true
pkill -f "antigravity-bar" 2>/dev/null || true

# Start fresh in background
nohup "$DIR/bin/antigravity-bar" > /dev/null 2>&1 &
disown

echo "⚡ AntigravityBar is running in your top macOS menu bar!"
