#!/bin/bash
# HavaliDuvar.saver (ekran koruyucu) paketini derler ve ~/Library/Screen Savers'a kurar
set -e
cd "$(dirname "$0")"
S=Sources/HavaliDuvar
OUT=saver/HavaliDuvar.saver
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
swiftc -emit-library -Xlinker -bundle -module-name HavaliSaver -target arm64-apple-macos14.0 -O \
  -framework ScreenSaver -framework SwiftUI -framework AppKit -framework AVFoundation \
  $S/EffectsCore.swift $S/SceneRender.swift $S/SaverClock.swift saver/SaverView.swift \
  -o "$OUT/Contents/MacOS/HavaliDuvar"
cat > "$OUT/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HavaliDuvar</string>
<key>CFBundleDisplayName</key><string>HavaliDuvar</string>
<key>CFBundleIdentifier</key><string>local.havaliduvar.saver</string>
<key>CFBundleExecutable</key><string>HavaliDuvar</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSPrincipalClass</key><string>HavaliSaverView</string>
</dict></plist>
PL
codesign --force --sign - "$OUT" 2>/dev/null || true
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$HOME/Library/Screen Savers/HavaliDuvar.saver"
cp -R "$OUT" "$HOME/Library/Screen Savers/"
# Sistem eski sürümü bellekte tutar; yeni sürüm yüklensin diye çalışan koruyucu süreçlerini kapat
killall legacyScreenSaver ScreenSaverEngine 2>/dev/null || true
echo "Kuruldu: $HOME/Library/Screen Savers/HavaliDuvar.saver"
