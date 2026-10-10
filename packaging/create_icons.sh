#!/bin/bash
# Create icons for Portix (macOS .icns and Windows .ico)
# Usage: ./create_icons.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$PROJECT_ROOT/portix_app/assets/icons"
OUTPUT_DIR="$PROJECT_ROOT/packaging/icons"

mkdir -p "$OUTPUT_DIR"

# Source PNG file (adaptive foreground)
SOURCE_PNG="$ASSETS_DIR/portix_adaptive_foreground.png"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "Source icon not found: $SOURCE_PNG"
    echo "Please ensure portix_adaptive_foreground.png exists"
    exit 1
fi

echo "Creating icons from $SOURCE_PNG"

# Check for ImageMagick
if command -v convert &> /dev/null; then
    echo "Using ImageMagick for conversion..."
    
    # Create Windows .ico (multi-size)
    convert "$SOURCE_PNG" \
        -define icon:auto-resize=16,32,48,64,96,128,256 \
        "$OUTPUT_DIR/portix.ico"
    echo "Created: $OUTPUT_DIR/portix.ico"
    
    # Create macOS .icns
    # First create PNG files at required sizes
    mkdir -p /tmp/portix_icon_cache
    convert "$SOURCE_PNG" -resize 16x16   /tmp/portix_icon_cache/icon_16x16.png
    convert "$SOURCE_PNG" -resize 32x32   /tmp/portix_icon_cache/icon_16x16@2x.png
    convert "$SOURCE_PNG" -resize 32x32   /tmp/portix_icon_cache/icon_32x32.png
    convert "$SOURCE_PNG" -resize 48x48   /tmp/portix_icon_cache/icon_32x32@2x.png
    convert "$SOURCE_PNG" -resize 128x128 /tmp/portix_icon_cache/icon_128x128.png
    convert "$SOURCE_PNG" -resize 128x128 /tmp/portix_icon_cache/icon_128x128@2x.png
    convert "$SOURCE_PNG" -resize 256x256 /tmp/portix_icon_cache/icon_256x256.png
    convert "$SOURCE_PNG" -resize 512x512 /tmp/portix_icon_cache/icon_256x256@2x.png
    convert "$SOURCE_PNG" -resize 1024x1024 /tmp/portix_icon_cache/icon_512x512.png
    convert "$SOURCE_PNG" -resize 1024x1024 /tmp/portix_icon_cache/icon_512x512@2x.png
    
    # Create ICNS file
    iconutil -c icns /tmp/portix_icon_cache -o "$OUTPUT_DIR/portix.icns"
    echo "Created: $OUTPUT_DIR/portix.icns"
    
    # Cleanup
    rm -rf /tmp/portix_icon_cache
    
else
    echo "ImageMagick not found. Installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install imagemagick
        $0
    else
        echo "Please install ImageMagick to create icons"
        echo "On macOS: brew install imagemagick"
        echo "On Ubuntu: sudo apt install imagemagick"
        echo "On Windows: choco install imagemagick"
        exit 1
    fi
fi

echo ""
echo "Icons created successfully!"
echo "  - Windows: $OUTPUT_DIR/portix.ico"
echo "  - macOS:   $OUTPUT_DIR/portix.icns"