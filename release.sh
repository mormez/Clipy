#!/bin/bash
set -e

# Builds a Release configuration build, zips it, signs it for Sparkle,
# and prints the <item> block to add to docs/appcast.xml.
#
# Usage: ./release.sh <marketing-version> <build-number>
# Example: ./release.sh 1.1.0 2

VERSION=$1
BUILD=$2

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  echo "Usage: ./release.sh <marketing-version> <build-number>"
  echo "Example: ./release.sh 1.1.0 2"
  exit 1
fi

# Bump version numbers
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Sources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Sources/Info.plist

echo "Building Modern Clipboard $VERSION ($BUILD) — Release configuration..."
xcodebuild \
  -project "Modern Clipboard.xcodeproj" \
  -scheme "Modern Clipboard" \
  -configuration Release \
  -derivedDataPath build/ReleaseDerivedData \
  build

APP=$(find build/ReleaseDerivedData -name "Modern Clipboard.app" -type d -path "*Release*" | head -1)
if [ -z "$APP" ]; then
  echo "Build failed: app not found"
  exit 1
fi

RELEASE_DIR="releases/v$VERSION"
mkdir -p "$RELEASE_DIR"
ZIP_NAME="ModernClipboard-$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
echo ""
echo "✓ Built and zipped: $ZIP_PATH"

# Sign with Sparkle EdDSA key (from login keychain)
SIGN_UPDATE=$(find build/DerivedData/SourcePackages/artifacts/sparkle -name "sign_update" -path "*/bin/*" | head -1)
if [ -z "$SIGN_UPDATE" ]; then
  echo "Could not find sign_update tool. Run ./build.sh once first to fetch Sparkle dependencies."
  exit 1
fi

ENCLOSURE_ATTRS=$("$SIGN_UPDATE" "$ZIP_PATH")

echo ""
echo "==========================================================="
echo "1. Create a GitHub Release tagged v$VERSION:"
echo "   https://github.com/mormez/ModernClipboard/releases/new"
echo "   and upload: $ZIP_PATH"
echo ""
echo "2. Add this <item> inside <channel> in docs/appcast.xml:"
echo ""
cat <<EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/mormez/ModernClipboard/releases/download/v$VERSION/$ZIP_NAME"
                 $ENCLOSURE_ATTRS
                 type="application/octet-stream"/>
    </item>
EOF
echo ""
echo "3. Commit and push docs/appcast.xml"
echo "==========================================================="
