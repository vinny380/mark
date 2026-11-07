#!/bin/bash
# Builds Mark.app into ./build and installs it to /Applications.
# Usage: scripts/install.sh [--build-only]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Mark.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Mark" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Fonts "$APP/Contents/Resources/"
codesign --force -s - "$APP"

[[ "${1:-}" == "--build-only" ]] && { echo "Built $APP"; exit 0; }

rm -rf /Applications/Mark.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Mark.app
echo "Installed /Applications/Mark.app"
