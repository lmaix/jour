#!/bin/zsh
# Compile Jour.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="Jour.app"
BUNDLE_ID="com.stephane.Jour"
TESTS="${TMPDIR:-/tmp}/jour-tests"

echo "▸ Tests"
swiftc -O -o "$TESTS" Sources/Models.swift Sources/ICS.swift Sources/Feeds.swift Tests/main.swift
"$TESTS"

echo "▸ Compilation"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/Jour" Sources/*.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Jour</string>
  <key>CFBundleDisplayName</key><string>Jour</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Jour</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "▸ Installation dans ~/Applications"
mkdir -p ~/Applications
pkill -x Jour 2>/dev/null || true
# Avant le renommage l'app s'appelait ClaudeCalendarBar.app.
pkill -x ClaudeCalendarBar 2>/dev/null || true
rm -rf ~/Applications/ClaudeCalendarBar.app
rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✓ Lancée : ~/Applications/$APP"
