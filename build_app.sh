#!/bin/bash
# HavaliDuvar.app paketini oluşturur
set -e
cd "$(dirname "$0")"
swift build -c release
APP=HavaliDuvar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HavaliDuvar "$APP/Contents/MacOS/HavaliDuvar"
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET"
swift tools/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HavaliDuvar</string>
<key>CFBundleDisplayName</key><string>HavaliDuvar</string>
<key>CFBundleIdentifier</key><string>local.havaliduvar.app</string>
<key>CFBundleExecutable</key><string>HavaliDuvar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Hazır: $PWD/$APP"
