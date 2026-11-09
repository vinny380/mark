#!/bin/bash
# Builds Mark.app (with its Finder extension) into ./build and installs it to /Applications.
# Usage: scripts/install.sh [--build-only]
set -euo pipefail
cd "$(dirname "$0")/.."

# -Osize + stripped symbols: smallest binaries (Mark stays under 1 MB)
swift build -c release -Xswiftc -Osize
BIN=$(swift build -c release -Xswiftc -Osize --show-bin-path)
APP=build/Mark.app
EXT="$APP/Contents/PlugIns/MarkFinder.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
cp "$BIN/Mark" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Fonts "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp scripts/mark "$APP/Contents/Resources/mark"
cp "$BIN/MarkFinder" "$EXT/Contents/MacOS/"
cp Resources/MarkFinder-Info.plist "$EXT/Contents/Info.plist"

strip -x "$APP/Contents/MacOS/Mark" "$EXT/Contents/MacOS/MarkFinder"

# Ad-hoc signing (no developer certificate). Extension first: it must be sandboxed.
codesign --force -s - --entitlements Resources/MarkFinder.entitlements "$EXT"
codesign --force -s - "$APP"

[[ "${1:-}" == "--build-only" ]] && { echo "Built $APP"; exit 0; }

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
rm -rf /Applications/Mark.app
"$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
mv "$APP" /Applications/   # move, not copy: a second Mark.app would show up twice in Open With
"$LSREGISTER" -f /Applications/Mark.app
pluginkit -a /Applications/Mark.app/Contents/PlugIns/MarkFinder.appex
pluginkit -e use -i com.vinny.mark.finder
echo "Installed /Applications/Mark.app"

# `mark` in Terminal: link into ~/.local/bin (yours, usually on PATH) unless something else already owns the name.
CLI=/Applications/Mark.app/Contents/Resources/mark
LINK="$HOME/.local/bin/mark"
if [ ! -e "$LINK" ] || [ "$(readlink "$LINK")" = "$CLI" ]; then
  mkdir -p "$HOME/.local/bin" && ln -sf "$CLI" "$LINK" && echo "Linked $LINK"
else
  echo "Skipped linking $LINK (already exists). Add an alias: alias mark='$CLI'"
fi
echo "If 'New Markdown File' is missing from Finder's right-click menu: System Settings → General → Login Items & Extensions → File Providers / Finder → enable Mark."
