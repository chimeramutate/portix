#!/bin/bash
# Build Flutter macOS App (without rebuilding Rust library)
# Usage: ./build_flutter_app.sh
# 
# This script assumes Rust libraries are already built and available at:
# - portix_app/artifacts/libportix_serv.dylib
# - portix_app/artifacts/libportix_rdp.dylib

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORTIX_APP="$PROJECT_ROOT/portix_app"

echo -e "${GREEN}=== Building Portix Flutter macOS App ===${NC}"

# Check if Rust libraries exist
echo -e "${YELLOW}Checking Rust libraries...${NC}"
if [ ! -f "$PORTIX_APP/artifacts/libportix_serv.dylib" ]; then
    echo -e "${RED}Error: libportix_serv.dylib not found at $PORTIX_APP/artifacts/${NC}"
    echo "Build Rust libraries first or download from CI artifact"
    exit 1
fi

if [ ! -f "$PORTIX_APP/artifacts/libportix_rdp.dylib" ]; then
    echo -e "${RED}Error: libportix_rdp.dylib not found at $PORTIX_APP/artifacts/${NC}"
    echo "Build Rust libraries first or download from CI artifact"
    exit 1
fi

echo -e "${GREEN}Rust libraries found${NC}"

# Clean previous build
echo -e "${YELLOW}Cleaning previous Flutter build...${NC}"
rm -rf "$PORTIX_APP/build/macos"

# Build Flutter macOS
echo -e "${YELLOW}Building Flutter macOS...${NC}"
cd "$PORTIX_APP"
flutter build macos --release

# Find app bundle
APP_BUNDLE="$PORTIX_APP/build/macos/Build/Products/Release/Portix.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App bundle not found${NC}"
    exit 1
fi

# Copy libraries to app bundle
echo -e "${YELLOW}Bundling Rust libraries...${NC}"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
cp "$PORTIX_APP/artifacts/libportix_serv.dylib" "$MACOS_DIR/"
cp "$PORTIX_APP/artifacts/libportix_rdp.dylib" "$MACOS_DIR/"

# Codesign (optional - for development)
echo -e "${YELLOW}Codesigning...${NC}"
codesign --force --sign - \
    --entitlements "$PROJECT_ROOT/portix_app/macos/Runner/Release.entitlements" \
    "$MACOS_DIR/libportix_serv.dylib" 2>/dev/null || true
codesign --force --sign - \
    --entitlements "$PROJECT_ROOT/portix_app/macos/Runner/Release.entitlements" \
    "$MACOS_DIR/libportix_rdp.dylib" 2>/dev/null || true
codesign --force --sign - --deep "$APP_BUNDLE" 2>/dev/null || true

# Create zip
echo -e "${YELLOW}Creating ZIP...${NC}"
cd "$PROJECT_ROOT"
APP_NAME="Portix"
VERSION="${1:-dev}"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "dist/${ZIP_NAME}"

echo -e "${GREEN}=== Build Complete ===${NC}"
echo "Output: dist/${ZIP_NAME}"