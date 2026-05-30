#!/bin/zsh
# Finish a release whose notarization is now Accepted: staple the ticket onto
# the already-signed build, re-zip, upload to the GitHub release, and bump the
# Homebrew cask. Use this instead of re-running release.sh when the app is
# already built + signed + submitted (avoids rebuilding and re-submitting).
#
#   ./finish-release.sh
#
# `xcrun stapler staple` fails if Apple hasn't finished notarizing yet — that's
# the signal to wait longer.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Switchboard"
REPO="ikanc/switchboard"
BUILD_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"
TAP_DIR="${SWITCHBOARD_TAP_DIR:-$HOME/Code/Mac/homebrew-tap}"

VERSION=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v$VERSION"
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

[[ -d "$APP" ]] || { echo "✗ No signed build at $APP — run ./release.sh first."; exit 1; }

echo "→ Stapling notarization ticket (fails if not yet Accepted)..."
xcrun stapler staple "$APP"

echo "→ Verifying Gatekeeper acceptance..."
spctl --assess --type execute --verbose=2 "$APP"

echo "→ Re-zipping stapled app..."
mkdir -p "$DIST_DIR"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

echo "→ Uploading to release $TAG..."
gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber

echo "→ Bumping Homebrew cask..."
CASK="$TAP_DIR/Casks/switchboard.rb"
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
/usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
if git -C "$TAP_DIR" diff --quiet -- Casks/switchboard.rb; then
    echo "  cask already current"
else
    git -C "$TAP_DIR" add Casks/switchboard.rb
    git -C "$TAP_DIR" commit -q -m "switchboard $VERSION (notarized)"
    git -C "$TAP_DIR" push -q origin main
fi

echo ""
echo "✓ Notarized $APP_NAME $VERSION shipped. Gatekeeper will accept it on install."
