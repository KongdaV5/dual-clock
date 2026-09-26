#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

APP="$DIR/DualClock.app"
TMP="$(mktemp -d /tmp/dualclock-build.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "Building DualClock v3.3.6 with clang..."
mkdir -p "$TMP/DualClock.app/Contents/MacOS"
mkdir -p "$TMP/DualClock.app/Contents/Resources/holidays"

cat > "$TMP/DualClock.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DualClock</string>
<key>CFBundleIdentifier</key><string>local.kongda.DualClockMenuBar</string>
<key>CFBundleName</key><string>DualClock</string>
<key>CFBundleDisplayName</key><string>DualClock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>3.3.6</string>
<key>CFBundleVersion</key><string>336</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cp "$DIR"/Resources/*.json "$TMP/DualClock.app/Contents/Resources/holidays/"
cp "$DIR"/Resources/AppIcon.icns "$TMP/DualClock.app/Contents/Resources/AppIcon.icns"

xcrun clang \
  -fobjc-arc \
  -O2 \
  -Wall \
  -Wextra \
  -Werror \
  -arch arm64 \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  "$DIR/main.m" \
  -o "$TMP/DualClock.app/Contents/MacOS/DualClock"

test -x "$TMP/DualClock.app/Contents/MacOS/DualClock"
file "$TMP/DualClock.app/Contents/MacOS/DualClock" | grep -q "Mach-O"
plutil -lint "$TMP/DualClock.app/Contents/Info.plist" >/dev/null

codesign --force --deep --sign - "$TMP/DualClock.app" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$TMP/DualClock.app" >/dev/null 2>&1 || true

rm -rf "$APP"
mv "$TMP/DualClock.app" "$APP"

echo
echo "SUCCESS"
ls -l "$APP/Contents/MacOS/DualClock"
file "$APP/Contents/MacOS/DualClock"
echo
echo "Built only; not auto-opened, to avoid duplicate menu-bar instances."

echo
echo "Installing to /Applications..."
killall DualClock 2>/dev/null || true
rm -rf /Applications/DualClock.app
cp -R "$DIR/DualClock.app" /Applications/
xattr -dr com.apple.quarantine /Applications/DualClock.app >/dev/null 2>&1 || true
codesign --force --deep --sign - /Applications/DualClock.app >/dev/null 2>&1 || true

open /Applications/DualClock.app

echo
echo "Installed and launched:"
echo "  /Applications/DualClock.app"
