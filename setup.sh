#!/bin/zsh
set -e

cd "$(dirname "$0")"

echo "=== Switchboard - Setup ==="

# Check for xcodegen
if ! command -v xcodegen &>/dev/null; then
    echo "Installing xcodegen via Homebrew..."
    brew install xcodegen
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done! Opening in Xcode..."
open Switchboard.xcodeproj

echo ""
echo "To build & run:"
echo "  1. Press Cmd+R in Xcode"
echo "  2. The bolt icon will appear in your menu bar"
echo ""
echo "To build from CLI:"
echo "  xcodebuild -project Switchboard.xcodeproj -scheme Switchboard -configuration Release build"
