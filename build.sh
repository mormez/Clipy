#!/bin/bash
set -e

echo "Building Clipy..."
xcodebuild \
  -project Clipy.xcodeproj \
  -scheme Clipy \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build

APP=$(find build/DerivedData -name "Clipy.app" -type d | head -1)
echo ""
echo "✓ Build succeeded: $APP"
echo ""
echo "To run: open \"$APP\""
