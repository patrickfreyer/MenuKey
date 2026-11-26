#!/bin/zsh
# Builds JumpKey.app and installs it into /Applications (or ~/Applications).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/JumpKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/JumpKey "$APP/Contents/MacOS/JumpKey"
[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>JumpKey</string>
  <key>CFBundleDisplayName</key><string>JumpKey</string>
  <key>CFBundleIdentifier</key><string>com.patrickfreyer.JumpKey</string>
  <key>CFBundleExecutable</key><string>JumpKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Use a real identity if one exists, else ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

DEST=/Applications
[[ -w $DEST ]] || DEST=~/Applications
mkdir -p "$DEST"
pkill -x JumpKey 2>/dev/null || true
rm -rf "$DEST/JumpKey.app"
cp -R "$APP" "$DEST/"
echo "Installed $DEST/JumpKey.app (signed: ${IDENTITY:-ad-hoc})"
