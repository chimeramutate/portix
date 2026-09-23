#!/bin/bash
# Build DMG for Portix macOS
# Usage: ./build_dmg.sh [version] [build_number]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
APP_NAME="Portix"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORTIX_APP="$PROJECT_ROOT/portix_app"
BUNDLE_DIR="$PROJECT_ROOT/bundle"
DMG_DIR="$PROJECT_ROOT/dist"
DMG_STAGING="$PROJECT_ROOT/.dmg_staging"

echo -e "${GREEN}=== Building Portix DMG ===${NC}"
echo "Version: $VERSION"
echo "Build Number: $BUILD_NUMBER"
echo "Project Root: $PROJECT_ROOT"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script must be run on macOS${NC}"
    exit 1
fi

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf "$DMG_DIR"
rm -rf "$BUNDLE_DIR"
rm -rf "$DMG_STAGING"
rm -rf "$PORTIX_APP/build"
mkdir -p "$DMG_DIR"
mkdir -p "$DMG_STAGING"

# Build Rust libraries first
echo -e "${YELLOW}Building Rust libraries...${NC}"

# Build SSH library
cd "$PROJECT_ROOT/portix_serv"
cargo build --release
cp target/release/libportix_serv.dylib "$PORTIX_APP/artifacts/libportix_serv.dylib"
echo -e "${GREEN}SSH library built successfully${NC}"

# Build RDP library
cd "$PROJECT_ROOT/portix_rdp"
cargo build --release
cp target/release/libportix_rdp.dylib "$PORTIX_APP/artifacts/libportix_rdp.dylib"
echo -e "${GREEN}RDP library built successfully${NC}"

# Build Flutter macOS app
echo -e "${YELLOW}Building Flutter macOS app...${NC}"
cd "$PORTIX_APP"
flutter build macos \
    --dart-define=FLUTTER_BUILD_NAME="$VERSION" \
    --dart-define=FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
    --build-name="$VERSION" \
    --build-number="$BUILD_NUMBER"

echo -e "${GREEN}Flutter app built successfully${NC}"

# Create app staging directory
echo -e "${YELLOW}Preparing DMG staging...${NC}"

# Copy the app bundle
APP_BUNDLE="$PORTIX_APP/build/macos/Build/Products/Release/${APP_NAME}.app"
if [ -d "$APP_BUNDLE" ]; then
    cp -R "$APP_BUNDLE" "$DMG_STAGING/${APP_NAME}.app"
else
    echo -e "${RED}Error: App bundle not found at $APP_BUNDLE${NC}"
    exit 1
fi

# Copy readme
README_FILE="$PROJECT_ROOT/README.md"
if [ -f "$README_FILE" ]; then
    cp "$README_FILE" "$DMG_STAGING/README.txt"
fi

# Create Applications folder reference
touch "$DMG_STAGING/Applications"

# Build DMG using hdiutil
echo -e "${YELLOW}Creating DMG...${NC}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
RAW_DMG="/tmp/${APP_NAME}-raw.dmg"

# Create uncompressed DMG first
hdiutil create -fs HFS+ -volname "$APP_NAME" -srcfolder "$DMG_STAGING" "$RAW_DMG"

# Convert to compressed DMG
hdiutil convert "$RAW_DMG" -format UDZO -o "$DMG_PATH"

# Cleanup temp files
rm -f "$RAW_DMG"

echo -e "${GREEN}DMG created at: $DMG_PATH${NC}"

# Verify DMG
echo -e "${YELLOW}Verifying DMG...${NC}"
hdiutil verify "$DMG_PATH"
echo -e "${GREEN}DMG verified successfully${NC}"

# Create zip for fallback
echo -e "${YELLOW}Creating zip backup...${NC}"
cd "$BUNDLE_DIR"
zip -r "$DMG_DIR/${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app"
echo -e "${GREEN}Zip created at: $DMG_DIR/${APP_NAME}-${VERSION}.zip${NC}"

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
cd "$PROJECT_ROOT"
rm -rf "$BUNDLE_DIR"
rm -rf "$DMG_STAGING"

echo -e "${GREEN}=== DMG Build Complete ===${NC}"
echo "DMG: $DMG_PATH"
echo "Zip: $DMG_DIR/${APP_NAME}-${VERSION}.zip"

# Generate checksums
cd "$DMG_DIR"
shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256"
echo -e "${GREEN}Checksums generated${NC}"