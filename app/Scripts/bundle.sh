#!/usr/bin/env bash
# Assemble Sonocles.app from the SwiftPM executable.
#
# SwiftPM builds a bare Mach-O; macOS needs a bundle. That is not ceremony —
# the Info.plist is what carries LSUIElement (no Dock icon, no app switcher)
# and, more importantly, what gives the app its own TCC identity. Run as a bare
# executable, microphone permission attaches to whatever terminal launched it,
# which is why the original spike asked you to grant Terminal mic access by
# hand. A bundle gets its own entry in System Settings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
DIST="$ROOT/../dist"
APP="$DIST/Sonocles.app"

# One invocation, not two. --show-bin-path is cheap but it still plans the
# build, and there is no reason to do that twice for a path we can ask for once.
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
swift build -c "$CONFIG" --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Sonocles" "$APP/Contents/MacOS/Sonocles"
cp "$BIN/sonocles-cli" "$APP/Contents/Resources/sonocles-cli"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>build.artisan.sonocles</string>
    <key>CFBundleName</key><string>Sonocles</string>
    <key>CFBundleDisplayName</key><string>Sonocles</string>
    <key>CFBundleExecutable</key><string>Sonocles</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Sonocles listens to your microphone so it can stream what you say to the tools that follow along.</string>
</dict>
</plist>
PLIST

# Ad-hoc unless SIGN_ID names a real identity. Ad-hoc signatures change on every
# build, so macOS may re-ask for the microphone after a rebuild; a Developer ID
# keeps one permission across rebuilds. Note that switching between the two
# makes this a *different app* to TCC — an existing grant does not carry over.
#
# The entitlements are not optional. The hardened runtime gates the microphone
# on com.apple.security.device.audio-input before TCC is consulted, so signing
# with --options runtime and no entitlements produces an app that cannot record
# and cannot ask to.
SIGN="${SIGN_ID:--}"
codesign --force --deep --options runtime \
  --entitlements "$ROOT/Scripts/Sonocles.entitlements" \
  --sign "$SIGN" "$APP"

echo "built $APP"
