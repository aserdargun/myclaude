#!/bin/bash
# Build myClaude as a proper macOS .app bundle with Info.plist
# so that notifications and bundle identifier work correctly.

set -e

APP_NAME="myClaude"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building MyClaude..."
cd MyClaude
swift build -c release 2>&1
cd ..

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp "MyClaude/.build/release/MyClaude" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "MyClaude/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy icon if available
if [ -f "MyClaude/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" ]; then
    cp "MyClaude/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" "${RESOURCES_DIR}/AppIcon.png"
    echo "App icon copied."
fi

echo ""
echo "Built: ${BUNDLE_DIR}"
echo "Run with: open ${BUNDLE_DIR}"
echo "Or:       ./${MACOS_DIR}/${APP_NAME}"
