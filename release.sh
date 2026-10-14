#!/bin/zsh
# Build a signed, notarized, universal ClaudeCalendarBar.app and zip it for a GitHub release.
#
#   ./release.sh 1.0
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your login Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials stored in the Keychain under the profile name below:
#        xcrun notarytool store-credentials claude-usage-bar --apple-id <you@example.com> --team-id <TEAMID>
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>, e.g. ./release.sh 1.0}"
PROFILE="${NOTARY_PROFILE:-claude-usage-bar}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "✗ No 'Developer ID Application' certificate in the Keychain (see the header of this script)."; exit 1; }

BUNDLE_ID="com.stephane.ClaudeCalendarBar"
OUT="dist"
APP="$OUT/ClaudeCalendarBar.app"
ZIP="$OUT/ClaudeCalendarBar-$VERSION.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Tests"
swiftc -O -o "$TMP/tests" Sources/Models.swift Sources/ICS.swift Sources/Feeds.swift Tests/main.swift
"$TMP/tests" > /dev/null

echo "▸ Universal build $VERSION"
rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "$TMP/ClaudeCalendarBar-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/ClaudeCalendarBar" "$TMP"/ClaudeCalendarBar-{arm64,x86_64}
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeCalendarBar</string>
  <key>CFBundleDisplayName</key><string>Claude Calendar</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD)</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>ClaudeCalendarBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "▸ Signing with $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$TMP/upload.zip"
xcrun notarytool submit "$TMP/upload.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ $ZIP — attach it to a GitHub release tagged v$VERSION"
