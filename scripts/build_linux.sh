#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"
DIST_DIR="$ROOT_DIR/dist-flutter"

echo "=== [1/4] Building Flutter Linux Release ==="
cd "$MOBILE_DIR"
flutter build linux --release

echo "=== [2/4] Preparing Debian package structure ==="
PKG_NAME="tadu-cloud-ai-agent-flutter_1.3.0_amd64"
PKG_DIR="$DIST_DIR/$PKG_NAME"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/opt/tadu-cloud-ai-agent"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy Linux release bundle
cp -r "$MOBILE_DIR/build/linux/x64/release/bundle/"* "$PKG_DIR/opt/tadu-cloud-ai-agent/"

# Symlink
ln -sf /opt/tadu-cloud-ai-agent/agent_mxh_auto "$PKG_DIR/usr/bin/tadu-cloud-ai-agent"

# Icon
cp "$MOBILE_DIR/assets/icon.png" "$PKG_DIR/usr/share/icons/hicolor/512x512/apps/tadu-cloud-ai-agent.png"

# Desktop Launcher
cat << 'DESKTOP_EOF' > "$PKG_DIR/usr/share/applications/tadu-cloud-ai-agent.desktop"
[Desktop Entry]
Name=MXH tự động
Comment=MXH tự động Native Desktop Application
Exec=/opt/tadu-cloud-ai-agent/agent_mxh_auto
Icon=tadu-cloud-ai-agent
Terminal=false
Type=Application
Categories=Development;Utility;
DESKTOP_EOF

# Control file
cat << 'CONTROL_EOF' > "$PKG_DIR/DEBIAN/control"
Package: tadu-cloud-ai-agent-flutter
Version: 1.3.0
Section: devel
Priority: optional
Architecture: amd64
Maintainer: Tadu Cloud Team <support@tadu.vn>
Description: MXH tự động Native Flutter Desktop Application
 High performance, lightweight native Linux desktop client for MXH tự động.
CONTROL_EOF

echo "=== [3/4] Packaging .deb installer ==="
dpkg-deb --build "$PKG_DIR" "$DIST_DIR/$PKG_NAME.deb"

echo "=== [4/4] Creating portable .tar.gz bundle ==="
cd "$MOBILE_DIR/build/linux/x64/release/bundle"
tar -czf "$DIST_DIR/tadu-cloud-ai-agent-flutter-linux-x64.tar.gz" .

echo "=== Done! Files generated in $DIST_DIR ==="
ls -lh "$DIST_DIR"
