#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$PROJECT_ROOT"
BIN_DIR="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT")"
APP="$PROJECT_ROOT/dist/NetCharge.app"
ICON_SOURCE="$PROJECT_ROOT/design/icon-03-limit-ring.png"
ICONSET="$PROJECT_ROOT/.build/NetCharge.iconset"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NetCharge" "$APP/Contents/MacOS/NetCharge"
cp "$BIN_DIR/netcharge-helper" "$APP/Contents/Resources/netcharge-helper"
cp "$PROJECT_ROOT/scripts/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
chmod 755 "$APP/Contents/MacOS/NetCharge" "$APP/Contents/Resources/netcharge-helper"

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -s format png -z "$doubled" "$doubled" "$ICON_SOURCE" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/NetCharge.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleExecutable</key><string>NetCharge</string>
<key>CFBundleIdentifier</key><string>com.netcharge.app</string>
<key>CFBundleIconFile</key><string>NetCharge.icns</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>NetCharge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "$APP"
