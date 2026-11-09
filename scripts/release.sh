#!/bin/bash
# Builds the release zip people download (and Homebrew installs), and prints its SHA-256 for the cask.
# Usage: scripts/release.sh   → dist/Mark-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
scripts/install.sh --build-only
mkdir -p dist
ZIP="dist/Mark-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Mark.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo
echo "Built $ZIP ($(du -k "$ZIP" | cut -f1) KB zipped, $(du -sk build/Mark.app | cut -f1) KB installed)"
echo "version \"$VERSION\""
echo "sha256 \"$SHA\""
