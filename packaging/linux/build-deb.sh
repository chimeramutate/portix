#!/bin/bash
set -euo pipefail

# Build a .deb package from the Flutter Linux bundle.
#
# Usage:
#   ./packaging/linux/build-deb.sh 1.0.1
#
# Debian Version MUST start with a digit. Do not pass a branch name
# such as "develop" here. The CI workflow resolves the application
# version from portix_app/pubspec.yaml.

VERSION="${1:-1.0.0}"
ARCH="amd64"
PKG_NAME="portix"

BUNDLE_DIR="portix_app/build/linux/x64/release/bundle"
OUTPUT_DIR="portix_app/build/linux/deb"
DEB_ROOT="$OUTPUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}"

# Debian package versions must start with a digit.
if ! [[ "$VERSION" =~ ^[0-9]+([.][0-9]+){0,3}([+~-][0-9A-Za-z.+:~-]+)?$ ]]; then
  echo "Error: Invalid Debian package version: $VERSION"
  echo "Example: 1.0.1"
  exit 1
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: Bundle not found at $BUNDLE_DIR"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

if [ ! -f "$BUNDLE_DIR/portix" ]; then
  echo "Error: Flutter executable not found at $BUNDLE_DIR/portix"
  exit 1
fi

echo "Building .deb package v${VERSION}..."

# Clean previous build.
rm -rf "$DEB_ROOT"

# Create Debian directory structure.
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/opt/portix"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps"

# Copy the complete Flutter bundle.
cp -a "$BUNDLE_DIR"/. "$DEB_ROOT/opt/portix/"

chmod +x "$DEB_ROOT/opt/portix/portix"

# IMPORTANT:
# The Flutter/Rust Linux loader expects the native libraries next to
# the application executable. The CI bundle step places both libraries
# directly in bundle/, so keep them directly in /opt/portix/.
for lib in libportix_serv.so libportix_rdp.so; do
  if [ ! -f "$DEB_ROOT/opt/portix/$lib" ]; then
    echo "ERROR: Required Rust library is missing from bundle: $lib"
    echo ""
    echo "Expected:"
    echo "  $DEB_ROOT/opt/portix/$lib"
    echo ""
    echo "The CI build must copy the Rust library into:"
    echo "  $BUNDLE_DIR/$lib"
    exit 1
  fi

  echo "Found Rust library: $lib"
done

# Create launcher symlink.
ln -sf /opt/portix/portix "$DEB_ROOT/usr/bin/portix"

# Copy icon.
if [ -f "assets/icons/portix_launcher.png" ]; then
  cp "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/portix.png"

  cp "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/portix.png"

  cp "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps/portix.png"
else
  echo "Warning: assets/icons/portix_launcher.png not found"
fi

# Create .desktop file.
cat > "$DEB_ROOT/usr/share/applications/portix.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Portix
Comment=SSH Client with SFTP, Terminal Workspace, and Remote Desktop
Exec=/opt/portix/portix
Icon=portix
Terminal=false
Categories=Network;RemoteAccess;System;
Keywords=ssh;sftp;terminal;remote;rdp;desktop;
StartupWMClass=portix
EOF

# Create Debian control file.
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libsecret-1-0, libgcrypt20
Maintainer: Asepimam <asepimam@portix.dev>
Description: Portix SSH and Remote Desktop Client
 Modern remote access client built with Flutter and Rust.
 Features multi-tab terminal sessions, split workspace,
 SFTP file manager, remote file browsing, SSH support,
 and remote desktop support.
Homepage: https://github.com/Asepimam/portix
EOF

# Create post-install script.
cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

update-desktop-database /usr/share/applications/ 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true

exit 0
EOF

chmod 755 "$DEB_ROOT/DEBIAN/postinst"

# Verify package contents before building.
echo ""
echo "Package contents:"
find "$DEB_ROOT/opt/portix" \
  -maxdepth 1 \
  -type f \
  -printf '%f\n' |
  sort

echo ""
echo "Verifying required libraries..."

test -f "$DEB_ROOT/opt/portix/libportix_serv.so"
test -f "$DEB_ROOT/opt/portix/libportix_rdp.so"

# Build .deb.
dpkg-deb --build "$DEB_ROOT"

DEB_FILE="${DEB_ROOT}.deb"

echo ""
echo "✓ Package built:"
echo "  $DEB_FILE"
echo ""
echo "Install with:"
echo "  sudo dpkg -i \"$DEB_FILE\""
echo ""
echo "Or:"
echo "  sudo apt install \"$DEB_FILE\""