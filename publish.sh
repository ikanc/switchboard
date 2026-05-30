#!/bin/zsh
# Build Switchboard (Release) and install it to /Applications.
#
# Usage:
#   ./publish.sh                # build current version and install
#   ./publish.sh patch          # bump 1.0.0 -> 1.0.1, then build + install
#   ./publish.sh minor          # bump 1.0.0 -> 1.1.0, then build + install
#   ./publish.sh major          # bump 1.0.0 -> 2.0.0, then build + install

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Switchboard"
SCHEME="$APP_NAME"
PROJECT="$APP_NAME.xcodeproj"
BUNDLE_ID="ca.codejitsu.switchboard"
BUILD_DIR="$(pwd)/build"
INSTALL_PATH="/Applications/$APP_NAME.app"

read_version() {
    grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

# --- optional version bump ---------------------------------------------------
BUMP="${1:-}"
if [[ -n "$BUMP" ]]; then
    CURRENT=$(read_version)
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
    case "$BUMP" in
        patch) PATCH=$((PATCH + 1)) ;;
        minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
        major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
        *) echo "Usage: $0 [patch|minor|major]"; exit 1 ;;
    esac
    NEW="$MAJOR.$MINOR.$PATCH"
    echo "→ Bumping version: $CURRENT → $NEW"
    /usr/bin/sed -i '' -E "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$NEW\"/" project.yml
    xcodegen generate >/dev/null
fi

VERSION=$(read_version)

# --- build -------------------------------------------------------------------
echo "→ Building $APP_NAME $VERSION (Release)..."
if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        build | xcbeautify
else
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        build
fi

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "✗ Build product not found at $BUILT_APP"
    exit 1
fi

# --- quit running instance ---------------------------------------------------
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "→ Quitting running $APP_NAME..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.5
    done
    pgrep -x "$APP_NAME" >/dev/null && pkill -x "$APP_NAME" 2>/dev/null || true
fi

# --- install -----------------------------------------------------------------
echo "→ Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

# --- relaunch ----------------------------------------------------------------
echo "→ Launching..."
open "$INSTALL_PATH"

echo "✓ Published $APP_NAME $VERSION"
