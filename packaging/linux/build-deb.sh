#!/bin/bash
set -e

# Build a .deb package from the Flutter Linux bundle.
# Usage: ./packaging/linux/build-deb.sh [version]

VERSION="${1:-1.0.0}"
ARCH="amd64"
PKG_NAME="portix"
BUNDLE_DIR="portix_app/build/linux/x64/release/bundle"
OUTPUT_DIR="portix_app/build/linux/deb"
DEB_ROOT="$OUTPUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: Bundle not found at $BUNDLE_DIR"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

echo "Building .deb package v${VERSION}..."

# Clean previous build
rm -rf "$DEB_ROOT"

# Create directory structure
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/opt/portix"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps"

# Copy bundle
cp -r "$BUNDLE_DIR"/* "$DEB_ROOT/opt/portix/"
chmod +x "$DEB_ROOT/opt/portix/portix"

# Create symlink
ln -sf /opt/portix/portix "$DEB_ROOT/usr/bin/portix"

# Copy icon
if [ -f "assets/icons/portix_launcher.png" ]; then
  cp "assets/icons/portix_launcher.png" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/portix.png"
  cp "assets/icons/portix_launcher.png" "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/portix.png"
  cp "assets/icons/portix_launcher.png" "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps/portix.png"
fi

# Create .desktop file
cat > "$DEB_ROOT/usr/share/applications/portix.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Portix
Comment=SSH Client with SFTP and Terminal Workspace
Exec=/opt/portix/portix
Icon=portix
Terminal=false
Categories=Network;RemoteAccess;System;
Keywords=ssh;sftp;terminal;remote;server;
StartupWMClass=portix
EOF

# Create control file
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libsecret-1-0, libgcrypt20
Maintainer: Asepimam <asepimam@portix.dev>
Description: Portix SSH Client
 Modern SSH client built with Flutter and Rust.
 Features multi-tab terminal sessions, split workspace,
 SFTP file manager, remote file browsing, command
 autocomplete, and cross-platform support.
Homepage: https://github.com/Asepimam/portix
EOF

# Create postinst script
cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
update-desktop-database /usr/share/applications/ 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true
EOF
chmod 755 "$DEB_ROOT/DEBIAN/postinst"

# Build .deb
dpkg-deb --build "$DEB_ROOT"

echo ""
echo "✓ Package built: ${DEB_ROOT}.deb"
echo "  Install with: sudo dpkg -i ${DEB_ROOT}.deb"
echo "  Or: sudo apt install ./${DEB_ROOT}.deb"
