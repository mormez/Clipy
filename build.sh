#!/bin/bash
set -e

echo "Building Clipy..."
xcodebuild \
  -project Clipy.xcodeproj \
  -scheme Clipy \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build

APP=$(find build/DerivedData -name "ModernClipy.app" -type d | head -1)

# Register with Launch Services so the icon appears everywhere
# (System Settings Accessibility list, Spotlight, etc.)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
touch "$APP"

echo ""
echo "✓ Build succeeded: $APP"
echo ""

# Kill the running instance (if any) and relaunch so changes are testable immediately
echo "Relaunching ModernClipy..."
killall ModernClipy 2>/dev/null || true
sleep 0.5
open "$APP"
echo "✓ App relaunched"
