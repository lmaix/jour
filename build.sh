#!/bin/zsh
# Compile ClaudeCalendarBar.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="ClaudeCalendarBar.app"
BUNDLE_ID="com.stephane.ClaudeCalendarBar"
TESTS="${TMPDIR:-/tmp}/claudecalendarbar-tests"

echo "▸ Tests"
swiftc -O -o "$TESTS" Sources/Models.swift Sources/Keychain.swift Sources/GoogleAuth.swift Tests/main.swift
"$TESTS"

echo "▸ Compilation"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ClaudeCalendarBar" Sources/*.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeCalendarBar</string>
  <key>CFBundleDisplayName</key><string>Claude Calendar</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>ClaudeCalendarBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

echo "▸ Installation dans ~/Applications"
mkdir -p ~/Applications
pkill -x ClaudeCalendarBar 2>/dev/null || true
rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✓ Lancée : ~/Applications/$APP"
