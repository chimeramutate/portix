#!/bin/bash
set -euo pipefail

# Build a .deb package from the Flutter Linux bundle.
#
# Usage:
#   ./packaging/linux/build-deb.sh [version]
#
# The Flutter bundle must already contain:
#   libportix_serv.so
#   libportix_rdp.so

VERSION="${1:-1.0.0}"
ARCH="amd64"
PKG_NAME="portix"

BUNDLE_DIR="portix_app/build/linux/x64/release/bundle"
OUTPUT_DIR="portix_app/build/linux/deb"
DEB_ROOT="$OUTPUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}"

echo "========================================"
echo "Building Portix .deb"
echo "========================================"
echo "Version : ${VERSION}"
echo "Arch    : ${ARCH}"
echo "Bundle  : ${BUNDLE_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Validate Debian version
# ---------------------------------------------------------------------------

if ! [[ "$VERSION" =~ ^[0-9][0-9A-Za-z.+:~-]*$ ]]; then
  echo "ERROR: Invalid Debian package version: ${VERSION}"
  echo "Version must start with a digit."
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate Flutter bundle
# ---------------------------------------------------------------------------

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: Flutter bundle not found:"
  echo "  $BUNDLE_DIR"
  echo ""
  echo "Run:"
  echo "  cd portix_app"
  echo "  flutter build linux --release"
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate main executable
# ---------------------------------------------------------------------------

if [ ! -f "$BUNDLE_DIR/portix" ]; then
  echo "ERROR: Portix executable not found:"
  echo "  $BUNDLE_DIR/portix"
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate Rust libraries
#
# IMPORTANT:
# The workflow copies the libraries directly into the Flutter bundle:
#
#   bundle/libportix_serv.so
#   bundle/libportix_rdp.so
#
# They are NOT expected under bundle/lib/.
# ---------------------------------------------------------------------------

for lib in \
  libportix_serv.so \
  libportix_rdp.so
do
  if [ ! -f "$BUNDLE_DIR/$lib" ]; then
    echo "ERROR: Required Rust library not found:"
    echo "  $BUNDLE_DIR/$lib"
    echo ""
    echo "Expected libraries:"
    echo "  $BUNDLE_DIR/libportix_serv.so"
    echo "  $BUNDLE_DIR/libportix_rdp.so"
    exit 1
  fi

  echo "Found Rust library:"
  ls -lh "$BUNDLE_DIR/$lib"
done

echo ""

# ---------------------------------------------------------------------------
# Clean previous build
# ---------------------------------------------------------------------------

rm -rf "$DEB_ROOT"

mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/opt/portix"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps"

# ---------------------------------------------------------------------------
# Copy Flutter bundle
# ---------------------------------------------------------------------------

echo "Copying Flutter bundle..."

cp -a "$BUNDLE_DIR/." "$DEB_ROOT/opt/portix/"

chmod +x "$DEB_ROOT/opt/portix/portix"

# ---------------------------------------------------------------------------
# Verify libraries after copy
# ---------------------------------------------------------------------------

echo ""
echo "Verifying packaged Rust libraries..."

for lib in \
  libportix_serv.so \
  libportix_rdp.so
do
  if [ ! -f "$DEB_ROOT/opt/portix/$lib" ]; then
    echo "ERROR: ${lib} was not copied into .deb package."
    exit 1
  fi

  echo "OK: /opt/portix/${lib}"
done

# ---------------------------------------------------------------------------
# Create executable symlink
# ---------------------------------------------------------------------------

ln -sf \
  /opt/portix/portix \
  "$DEB_ROOT/usr/bin/portix"

# ---------------------------------------------------------------------------
# Copy application icon
# ---------------------------------------------------------------------------

if [ -f "assets/icons/portix_launcher.png" ]; then

  cp \
    "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/portix.png"

  cp \
    "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/portix.png"

  cp \
    "assets/icons/portix_launcher.png" \
    "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps/portix.png"

else
  echo "WARNING: Application icon not found."
fi

# ---------------------------------------------------------------------------
# Create desktop entry
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Create control file
# ---------------------------------------------------------------------------

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
 autocomplete, RDP, and cross-platform support.
Homepage: https://github.com/Asepimam/portix
EOF

# ---------------------------------------------------------------------------
# Create postinst
# ---------------------------------------------------------------------------

cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

update-desktop-database \
  /usr/share/applications/ \
  2>/dev/null || true

gtk-update-icon-cache \
  /usr/share/icons/hicolor/ \
  2>/dev/null || true
EOF

chmod 755 "$DEB_ROOT/DEBIAN/postinst"

# ---------------------------------------------------------------------------
# Final package verification
# ---------------------------------------------------------------------------

echo ""
echo "Verifying package contents..."

if [ ! -f "$DEB_ROOT/opt/portix/libportix_serv.so" ]; then
  echo "ERROR: libportix_serv.so missing from package."
  exit 1
fi

if [ ! -f "$DEB_ROOT/opt/portix/libportix_rdp.so" ]; then
  echo "ERROR: libportix_rdp.so missing from package."
  exit 1
fi

echo "OK: libportix_serv.so"
echo "OK: libportix_rdp.so"

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------

echo ""
echo "Building .deb..."

dpkg-deb \
  --build \
  "$DEB_ROOT"

DEB_FILE="${DEB_ROOT}.deb"

echo ""
echo "========================================"
echo "✓ Package built successfully"
echo "========================================"
echo "File:"
echo "  ${DEB_FILE}"
echo ""

ls -lh "$DEB_FILE"

echo ""
echo "Package contents:"
dpkg-deb -c "$DEB_FILE" | grep -E \
  'libportix_(serv|rdp)\.so|/opt/portix/portix$|DEBIAN'

echo ""
echo "Install with:"
echo "  sudo dpkg -i ${DEB_FILE}"
echo ""
echo "Or:"
echo "  sudo apt install ./${DEB_FILE}"