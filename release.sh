#!/bin/zsh
# Cut a full release in one command:
#   1. build a Release .app and zip it
#   2. publish it as a GitHub Release (tag vX.Y.Z)
#   3. bump the Homebrew cask (version + sha256) and push the tap
#
#   ./release.sh
#
# Version comes from project.yml's MARKETING_VERSION — bump that (or run
# `./publish.sh minor`) before releasing. The tap is expected at
# ~/Code/Mac/homebrew-tap (override with SWITCHBOARD_TAP_DIR).
#
# Note: the app is currently unsigned/un-notarized. Homebrew quarantines
# unsigned casks, so first launch needs a right-click → Open (or
# `xattr -dr com.apple.quarantine`). Add Developer ID signing + notarization
# here later to remove that friction.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Switchboard"
REPO="ikanc/switchboard"
SCHEME="$APP_NAME"
PROJECT="$APP_NAME.xcodeproj"
BUILD_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"
# Local checkout of the Homebrew tap (github.com/ikanc/homebrew-tap). Override
# with SWITCHBOARD_TAP_DIR if it lives elsewhere.
TAP_DIR="${SWITCHBOARD_TAP_DIR:-$HOME/Code/Mac/homebrew-tap}"

VERSION=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v$VERSION"
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

echo "→ Building $APP_NAME $VERSION (Release)..."
xcodegen generate >/dev/null
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build >/dev/null

[[ -d "$APP" ]] || { echo "✗ Build product not found at $APP"; exit 1; }

echo "→ Packaging $ZIP..."
mkdir -p "$DIST_DIR"
rm -f "$ZIP"
# ditto preserves the bundle structure + resource forks (a plain `zip` can corrupt .app).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

echo "→ Publishing GitHub release $TAG..."
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber
else
    gh release create "$TAG" "$ZIP" \
        -R "$REPO" \
        --title "$APP_NAME $VERSION" \
        --generate-notes
fi

# --- update + push the Homebrew cask -----------------------------------------
CASK="$TAP_DIR/Casks/switchboard.rb"
if [[ -f "$CASK" ]]; then
    echo "→ Updating Homebrew cask..."
    /usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
    /usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
    if git -C "$TAP_DIR" diff --quiet -- Casks/switchboard.rb; then
        echo "  cask already at $VERSION — nothing to push"
    else
        git -C "$TAP_DIR" add Casks/switchboard.rb
        git -C "$TAP_DIR" commit -q -m "switchboard $VERSION"
        git -C "$TAP_DIR" push -q origin main
        echo "  cask bumped to $VERSION + pushed ✓"
    fi
else
    echo "⚠ Tap cask not found at $CASK — skipping cask update."
    echo "  Clone github.com/ikanc/homebrew-tap there (or set SWITCHBOARD_TAP_DIR),"
    echo "  or update it manually: version \"$VERSION\" / sha256 \"$SHA\""
fi

echo ""
echo "✓ Released $APP_NAME $VERSION"
echo "  Install: brew install --cask ikanc/tap/switchboard"
