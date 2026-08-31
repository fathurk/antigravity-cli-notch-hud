#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pkill -f "$DIR/bin/antigravity-bar" 2>/dev/null || true
pkill -f "antigravity-bar" 2>/dev/null || true

echo "AntigravityBar stopped."
