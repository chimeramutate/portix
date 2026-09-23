#!/bin/bash
# Build Windows EXE for Portix
# Usage: ./build_windows.sh [version] [build_number]
# Note: Cross-compile from macOS/Linux or run on Windows with Git Bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
APP_NAME="portix"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORTIX_APP="$PROJECT_ROOT/portix_app"
DIST_DIR="$PROJECT_ROOT/dist"
OUT_DIR="$DIST_DIR/windows"

echo -e "${GREEN}=== Building Portix Windows EXE ===${NC}"
echo "Version: $VERSION"
echo "Build Number: $BUILD_NUMBER"

# Create output directories
mkdir -p "$OUT_DIR"

# Function to build Rust library for Windows
build_rust_lib() {
    local lib_name=$1
    local project_dir=$2
    
    echo -e "${YELLOW}Building $lib_name for Windows...${NC}"
    cd "$project_dir"
    
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
        # Cross-compilation
        if rustup target list 2>/dev/null | grep -q "x86_64-pc-windows-gnu"; then
            cargo build --release --target x86_64-pc-windows-gnu
            # Copy the appropriate DLL file
            if [ -f "target/x86_64-pc-windows-gnu/lib${lib_name}.dll" ]; then
                cp "target/x86_64-pc-windows-gnu/lib${lib_name}.dll" "$PORTIX_APP/artifacts/"
            elif [ -f "target/x86_64-pc-windows-gnu/${lib_name}.dll" ]; then
                cp "target/x86_64-pc-windows-gnu/${lib_name}.dll" "$PORTIX_APP/artifacts/"
            fi
        else
            cargo build --release
            # Copy the appropriate DLL file
            if [ -f "target/release/lib${lib_name}.so" ]; then
                cp "target/release/lib${lib_name}.so" "$PORTIX_APP/artifacts/${lib_name}.dll"
            elif [ -f "target/release/${lib_name}.dll" ]; then
                cp "target/release/${lib_name}.dll" "$PORTIX_APP/artifacts/"
            fi
        fi
    else
        # Native Windows
        cargo build --release
        if [ -f "target/release/${lib_name}.dll" ]; then
            cp "target/release/${lib_name}.dll" "$PORTIX_APP/artifacts/"
        elif [ -f "target/release/lib${lib_name}.dll" ]; then
            cp "target/release/lib${lib_name}.dll" "$PORTIX_APP/artifacts/"
        fi
    fi
    echo -e "${GREEN}${lib_name} built successfully${NC}"
}

# Build SSH library
build_rust_lib "portix_serv" "$PROJECT_ROOT/portix_serv"

# Build RDP library
build_rust_lib "portix_rdp" "$PROJECT_ROOT/portix_rdp"

# Build Flutter Windows app
echo -e "${YELLOW}Building Flutter Windows app...${NC}"
cd "$PORTIX_APP"

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter not found${NC}"
    exit 1
fi

# Check if Windows toolchain is available
if flutter doctors 2>/dev/null | grep -q "Windows"; then
    echo -e "${GREEN}Windows toolchain detected${NC}"
    flutter build windows \
        --build-name="$VERSION" \
        --build-number="$BUILD_NUMBER"
else
    echo -e "${YELLOW}Windows toolchain not available. Cross-compilation may require additional setup.${NC}"
    echo "Building Flutter bundle..."
    flutter build bundle --no-pub
fi

echo -e "${GREEN}Flutter Windows build completed${NC}"

# Package the output
echo -e "${YELLOW}Packaging Windows output...${NC}"

# Find the built executable
BUILD_OUTPUT="$PORTIX_APP/build/windows/runner/Release"
if [ -d "$BUILD_OUTPUT" ]; then
    # Copy all files to output directory
    mkdir -p "$OUT_DIR"
    cp -R "$BUILD_OUTPUT"/* "$OUT_DIR/"
    
    # Create a simple archive
    cd "$OUT_DIR"
    rm -f "${APP_NAME}-${VERSION}-win-x64.zip"
    zip -r "${APP_NAME}-${VERSION}-win-x64.zip" *
    
    echo -e "${GREEN}Windows package created: ${OUT_DIR}/${APP_NAME}-${VERSION}-win-x64.zip${NC}"
else
    echo -e "${RED}Error: Build output not found at $BUILD_OUTPUT${NC}"
    echo "Check Flutter build logs"
    exit 1
fi

# Cleanup
cd "$PROJECT_ROOT"

echo -e "${GREEN}=== Windows Build Complete ===${NC}"
echo "Output: $OUT_DIR/${APP_NAME}-${VERSION}-win-x64.zip"

# Generate checksums
cd "$OUT_DIR"
shasum -a 256 "${APP_NAME}-${VERSION}-win-x64.zip" > "${APP_NAME}-${VERSION}-win-x64.zip.sha256"
echo -e "${GREEN}Checksums generated${NC}"