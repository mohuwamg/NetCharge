#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/dist/NetCharge.app"
STAGING="$PROJECT_ROOT/dist/dmg-root"
DMG="$PROJECT_ROOT/dist/NetCharge-macOS-arm64.dmg"

if [[ ! -d "$APP" ]]; then
    echo "请先运行 scripts/build-app.sh" >&2
    exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/NetCharge.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -quiet -ov -format UDZO -volname NetCharge -srcfolder "$STAGING" "$DMG"
hdiutil verify -quiet "$DMG"
rm -rf "$STAGING"
echo "$DMG"
