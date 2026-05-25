#!/usr/bin/env bash
#
# Builds KleanKeyboard.app from the Swift package.
#
# Requirements: macOS with the Xcode command-line tools (`xcode-select --install`).
# A full Xcode install is NOT required.
#
# Usage:
#   ./build_app.sh            # release build -> ./KleanKeyboard.app
#   ./build_app.sh --debug    # debug build
#   ./build_app.sh --run      # build, then launch the app

set -euo pipefail

CONFIG="release"
RUN_AFTER=0

for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --run)   RUN_AFTER=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: KleanKeyboard is a macOS app and must be built on macOS." >&2
    exit 1
fi

APP_NAME="KleanKeyboard"
APP_BUNDLE="${APP_NAME}.app"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR"

echo "==> Compiling ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: build did not produce $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# App icon: build AppIcon.icns from the committed iconset (iconutil ships with macOS).
if [[ -d "icon/AppIcon.iconset" ]]; then
    echo "==> Building app icon..."
    if iconutil -c icns "icon/AppIcon.iconset" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"; then
        :
    else
        echo "   (iconutil failed — app will run without a custom icon)"
    fi
fi

# Ad-hoc code signature so macOS keeps a stable identity for the Accessibility
# permission grant across rebuilds (otherwise you'd have to re-authorize each time).
echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || \
    echo "   (codesign skipped/failed — app will still run)"

echo "==> Done: ${ROOT_DIR}/${APP_BUNDLE}"
echo
echo "First launch: grant Accessibility access when prompted"
echo "(System Settings ▸ Privacy & Security ▸ Accessibility)."

if [[ "$RUN_AFTER" -eq 1 ]]; then
    echo "==> Launching..."
    open "$APP_BUNDLE"
fi
