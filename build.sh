#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p "$DIR/bin"
mkdir -p "$DIR/state"

echo "Compiling NotchPrompt.swift..."
swiftc -O "$DIR/NotchPrompt.swift" -o "$DIR/bin/notch-prompt"
chmod +x "$DIR/bin/notch-prompt"

echo "Compiling AntigravityBar.swift (Menu Bar App)..."
swiftc -O "$DIR/AntigravityBar.swift" -o "$DIR/bin/antigravity-bar"
chmod +x "$DIR/bin/antigravity-bar"

chmod +x "$DIR/dispatcher.py"

echo "Build complete! Binaries located at $DIR/bin/"
