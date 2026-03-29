#!/bin/bash
# Build myClaude as a proper macOS .app bundle with Info.plist
# so that notifications and bundle identifier work correctly.

set -e

APP_NAME="myClaude"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SRC="MyClaude/Resources/Assets.xcassets/AppIcon.appiconset"

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

# Create .icns from PNGs using iconutil
if [ -d "${ICON_SRC}" ]; then
    ICONSET_DIR="build/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"

    # Map PNGs to iconset naming convention
    [ -f "${ICON_SRC}/icon_16x16.png" ]   && cp "${ICON_SRC}/icon_16x16.png"   "${ICONSET_DIR}/icon_16x16.png"
    [ -f "${ICON_SRC}/icon_32x32.png" ]   && cp "${ICON_SRC}/icon_32x32.png"   "${ICONSET_DIR}/icon_16x16@2x.png"
    [ -f "${ICON_SRC}/icon_32x32.png" ]   && cp "${ICON_SRC}/icon_32x32.png"   "${ICONSET_DIR}/icon_32x32.png"
    [ -f "${ICON_SRC}/icon_64x64.png" ]   && cp "${ICON_SRC}/icon_64x64.png"   "${ICONSET_DIR}/icon_32x32@2x.png"
    [ -f "${ICON_SRC}/icon_128x128.png" ] && cp "${ICON_SRC}/icon_128x128.png" "${ICONSET_DIR}/icon_128x128.png"
    [ -f "${ICON_SRC}/icon_256x256.png" ] && cp "${ICON_SRC}/icon_256x256.png" "${ICONSET_DIR}/icon_128x128@2x.png"
    [ -f "${ICON_SRC}/icon_256x256.png" ] && cp "${ICON_SRC}/icon_256x256.png" "${ICONSET_DIR}/icon_256x256.png"
    [ -f "${ICON_SRC}/icon_512x512.png" ] && cp "${ICON_SRC}/icon_512x512.png" "${ICONSET_DIR}/icon_256x256@2x.png"
    [ -f "${ICON_SRC}/icon_512x512.png" ] && cp "${ICON_SRC}/icon_512x512.png" "${ICONSET_DIR}/icon_512x512.png"
    [ -f "${ICON_SRC}/icon_1024x1024.png" ] && cp "${ICON_SRC}/icon_1024x1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"

    iconutil -c icns -o "${RESOURCES_DIR}/AppIcon.icns" "${ICONSET_DIR}"
    rm -rf "${ICONSET_DIR}"
    echo "App icon created."
fi

echo ""
echo "Built: ${BUNDLE_DIR}"
echo "Run with: open ${BUNDLE_DIR}"
echo "Or:       ./${MACOS_DIR}/${APP_NAME}"
