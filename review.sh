#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN="$DIR/bin/artifact-reviewer"

if [ ! -f "$BIN" ]; then
    echo "🔨 Compiling Artifact Reviewer..."
    bash "$DIR/build.sh"
fi

if [ -n "$1" ]; then
    "$BIN" "$1" &
else
    "$BIN" &
fi
