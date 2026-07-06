#!/bin/bash
# Build LockGuard and install it to /Applications so macOS permissions
# (Accessibility/Camera/Keychain) attach to a stable path + identity.
# Run from the LockGuard/ directory.
set -e

PROJ="LockGuard.xcodeproj"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/LockGuard-deatrqylxjncywfcxabtkkxaevpl"
BUILT="$DERIVED/Build/Products/Debug/LockGuard.app"
DEST="/Applications/LockGuard.app"

echo "▸ Building…"
xcodebuild -project "$PROJ" -scheme LockGuard -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build >/dev/null

echo "▸ Installing to $DEST…"
pkill -f "LockGuard.app" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

echo "▸ Launching…"
open "$DEST"
echo "✓ Installed and launched: $DEST"
