#!/bin/zsh
# Build a Release .app, zip it, and publish it as a GitHub Release so the
# Homebrew cask can download it.
#
#   ./release.sh
#
# Reads the version from project.yml, tags it (vX.Y.Z), uploads the zip, and
# prints the version + sha256 + url to paste into the Homebrew cask.
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

echo ""
echo "✓ Released $APP_NAME $VERSION"
echo "  Update the Homebrew cask with:"
echo "    version \"$VERSION\""
echo "    sha256 \"$SHA\""
echo "    url    https://github.com/$REPO/releases/download/$TAG/$APP_NAME-$VERSION.zip"
