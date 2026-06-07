#!/bin/bash
set -e

echo "Building Modern Clipboard..."
xcodebuild \
  -project Clipy.xcodeproj \
  -scheme "Modern Clipboard" \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build

APP=$(find build/DerivedData -name "Modern Clipboard.app" -type d | head -1)

# Register with Launch Services so the icon appears everywhere
# (System Settings Accessibility list, Spotlight, etc.)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
touch "$APP"

echo ""
echo "✓ Build succeeded: $APP"
echo ""

# Kill the running instance (if any) and relaunch so changes are testable immediately
echo "Relaunching Modern Clipboard..."
killall "Modern Clipboard" 2>/dev/null || true
sleep 0.5
open "$APP"
echo "✓ App relaunched"
