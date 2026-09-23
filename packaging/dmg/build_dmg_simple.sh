#!/bin/bash
# Build Portix DMG (Flutter macOS App Only)
# Usage: ./build_dmg_simple.sh [version]
# 
# This script builds the Flutter macOS app and creates a DMG.
# Assumes Rust libraries are already built and placed in:
# - portix_app/artifacts/libportix_serv.dylib
# - portix_app/artifacts/libportix_rdp.dylib

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VERSION="${1:-dev}"
APP_NAME="Portix"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORTIX_APP="$PROJECT_ROOT/portix_app"
DIST_DIR="$PROJECT_ROOT/dist"

echo -e "${GREEN}=== Building Portix DMG ===${NC}"
echo "Version: $VERSION"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script must be run on macOS${NC}"
    exit 1
fi

# Clean
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$PORTIX_APP/build"

# Check Rust libraries exist
echo -e "${YELLOW}Checking Rust libraries...${NC}"
if [ ! -f "$PORTIX_APP/artifacts/libportix_serv.dylib" ]; then
    echo -e "${RED}Error: Rust libraries not found${NC}"
    echo "Please build Rust libraries first"
    exit 1
fi
echo -e "${GREEN}Rust libraries found${NC}"

# Build Flutter macOS
echo -e "${YELLOW}Building Flutter macOS app...${NC}"
cd "$PORTIX_APP"
flutter build macos --release

# Bundle libraries into app
echo -e "${YELLOW}Bundling libraries...${NC}"
APP_BUNDLE="$PORTIX_APP/build/macos/Build/Products/Release/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
cp "$PORTIX_APP/artifacts/libportix_serv.dylib" "$MACOS_DIR/"
cp "$PORTIX_APP/artifacts/libportix_rdp.dylib" "$MACOS_DIR/"

# Codesign (optional)
echo -e "${YELLOW}Codesigning...${NC}"
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

# Create DMG
echo -e "${YELLOW}Creating DMG...${NC}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# Create temp staging
TMP_STAGING="/tmp/portix_dmg_staging"
rm -rf "$TMP_STAGING"
mkdir -p "$TMP_STAGING"
cp -R "$APP_BUNDLE" "$TMP_STAGING/${APP_NAME}.app"

# Create DMG using hdiutil
hdiutil create -fs HFS+ -volname "$APP_NAME" -srcfolder "$TMP_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_STAGING"

# Verify
echo -e "${YELLOW}Verifying DMG...${NC}"
hdiutil verify "$DMG_PATH"

# Create zip as backup
echo -e "${YELLOW}Creating ZIP...${NC}"
cd "$TMP_STAGING" 2>/dev/null || cd "$PORTIX_APP"
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/${APP_NAME}-${VERSION}.zip" 2>/dev/null || \
    zip -r "$DIST_DIR/${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app" 2>/dev/null || \
    echo "Warning: Could not create zip"

# Checksums
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256" 2>/dev/null || \
    shasum -a 256 "${APP_NAME}-${VERSION}.zip" > "${APP_NAME}-${VERSION}.zip.sha256"

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo "DMG: $DMG_PATH"
ls -la "$DIST_DIR"