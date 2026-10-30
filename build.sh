#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p "$DIR/bin"
mkdir -p "$DIR/state"

echo "Compiling NotchPrompt.swift..."
swiftc -O -parse-as-library "$DIR/Sources/NotchHUDCore/ArtifactApproval.swift" "$DIR/NotchPrompt.swift" -o "$DIR/bin/notch-prompt"
chmod +x "$DIR/bin/notch-prompt"
codesign -s - --force "$DIR/bin/notch-prompt" 2>/dev/null || true

echo "Compiling AntigravityBar.swift (Menu Bar App)..."
swiftc -O -parse-as-library "$DIR/Sources/NotchHUDCore/ArtifactApproval.swift" "$DIR/AntigravityBar.swift" -o "$DIR/bin/antigravity-bar"
chmod +x "$DIR/bin/antigravity-bar"
codesign -s - --force "$DIR/bin/antigravity-bar" 2>/dev/null || true

echo "Compiling ArtifactReviewer.swift (Markdown Reviewer & Commenting)..."
swiftc -O -parse-as-library "$DIR/Sources/NotchHUDCore/ArtifactApproval.swift" "$DIR/ArtifactReviewer.swift" -o "$DIR/bin/artifact-reviewer"
chmod +x "$DIR/bin/artifact-reviewer"
codesign -s - --force "$DIR/bin/artifact-reviewer" 2>/dev/null || true

chmod +x "$DIR/dispatcher.py"
chmod +x "$DIR/review.sh"

echo "Build complete! Binaries located at $DIR/bin/"

# If LaunchAgent is registered, refresh launchd registration with the new binary hash
PLIST="$HOME/Library/LaunchAgents/com.antigravity.notchhud.plist"
if [ -f "$PLIST" ]; then
    echo "Refreshing macOS LaunchAgent registration..."
    launchctl bootout "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl kickstart -kp "gui/$(id -u)/com.antigravity.notchhud" 2>/dev/null || true
fi
