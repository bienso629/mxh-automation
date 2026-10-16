#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$APP_DIR/dist-flutter"

echo "========================================================"
echo " TAO BAN CAI DAT UBUNTU/DEBIAN CHO MXH TU DONG"
echo "========================================================"

cd "$APP_DIR"

if [ ! -f "$APP_DIR/build/linux/x64/release/bundle/agent_mxh_auto" ]; then
    echo "[1/4] Dang bien dich Flutter Linux Release..."
    flutter build linux --release
else
    echo "[1/4] Da co san ban bien dich Flutter Linux Release."
fi

echo "[2/4] Chuan bi cau truc goi cai dat .deb..."
PKG_NAME="mxh-tu-dong_1.0.0_amd64"
PKG_DIR="$DIST_DIR/$PKG_NAME"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/opt/mxh-tu-dong"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"

# Copy Linux release bundle
cp -r "$APP_DIR/build/linux/x64/release/bundle/"* "$PKG_DIR/opt/mxh-tu-dong/"

# Tao script khoi chay trong /usr/bin de chay truc tiep tu command line
cat << 'BIN_EOF' > "$PKG_DIR/usr/bin/mxh-tu-dong"
#!/bin/bash
export GDK_BACKEND=x11
if [ -x "/opt/mxh-tu-dong/agent_mxh_auto" ]; then
    exec /opt/mxh-tu-dong/agent_mxh_auto "$@"
elif [ -x "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" ]; then
    exec "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" "$@"
fi
BIN_EOF
chmod +x "$PKG_DIR/usr/bin/mxh-tu-dong"

# Icon day du kich thuoc chuan hicolor
python3 -c "
import os
from PIL import Image

src = '$APP_DIR/assets/icon.png'
sizes = [16, 24, 32, 48, 64, 128, 256, 512]
base = '$PKG_DIR/usr/share/icons/hicolor'
im = Image.open(src)
for s in sizes:
    d = os.path.join(base, f'{s}x{s}', 'apps')
    os.makedirs(d, exist_ok=True)
    resized = im.resize((s, s), getattr(Image, 'Resampling', Image).LANCZOS)
    for n in ['mxh-tu-dong', 'agent.mxh.auto', 'agent_mxh_auto']:
        resized.save(os.path.join(d, f'{n}.png'), format='PNG')
    if s == 256:
        pix_dir = '$PKG_DIR/usr/share/pixmaps'
        os.makedirs(pix_dir, exist_ok=True)
        for n in ['mxh-tu-dong', 'agent.mxh.auto', 'agent_mxh_auto']:
            resized.save(os.path.join(pix_dir, f'{n}.png'), format='PNG')
"

# Desktop Launcher
cat << 'DESKTOP_EOF' > "$PKG_DIR/usr/share/applications/mxh-tu-dong.desktop"
[Desktop Entry]
Name=Diễn viên MXH
Comment=Diễn viên MXH
Exec=/usr/bin/mxh-tu-dong
Icon=mxh-tu-dong
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
StartupWMClass=agent.mxh.auto
DESKTOP_EOF
chmod 644 "$PKG_DIR/usr/share/applications/mxh-tu-dong.desktop"

# Debian Pre-remove script (prerm) de don dep app cu khi go bo hoac nang cap
cat << 'PRERM_EOF' > "$PKG_DIR/DEBIAN/prerm"
#!/bin/bash
set -e
# Tat tien trinh cu neu dang chay
pkill -f "/opt/mxh-tu-dong/agent_mxh_auto" 2>/dev/null || true
exit 0
PRERM_EOF
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# Debian Post-installation script (postinst)
cat << 'POSTINST_EOF' > "$PKG_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

# Don dep cac file desktop override bi an o thu muc user neu co
for u_home in /home/*; do
    if [ -d "$u_home/.local/share/applications" ]; then
        rm -f "$u_home/.local/share/applications/mxh-tu-dong.desktop" 2>/dev/null || true
        rm -f "$u_home/.local/share/applications/agent.mxh.auto.desktop" 2>/dev/null || true
    fi
done

if which gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if which update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
    for u_home in /home/*; do
        if [ -d "$u_home/.local/share/applications" ]; then
            update-desktop-database "$u_home/.local/share/applications" 2>/dev/null || true
        fi
    done
fi
exit 0
POSTINST_EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# Debian Post-remove script (postrm)
cat << 'POSTRM_EOF' > "$PKG_DIR/DEBIAN/postrm"
#!/bin/bash
set -e
rm -rf /opt/mxh-tu-dong
if which gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if which update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
exit 0
POSTRM_EOF
chmod 755 "$PKG_DIR/DEBIAN/postrm"

# Debian Control file
cat << 'CONTROL_EOF' > "$PKG_DIR/DEBIAN/control"
Package: mxh-tu-dong
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Tadu Cloud Team <support@tadu.vn>
Depends: libc6, libgtk-3-0
Description: Phan mem AI quan ly MXH tu dong
 Ung dung Flutter Desktop quan ly MXH tu dong tren Ubuntu va Debian Linux.
CONTROL_EOF

echo "[3/4] Dong goi file cai dat .deb..."
mkdir -p "$DIST_DIR"
dpkg-deb --build "$PKG_DIR" "$DIST_DIR/mxh-tu-dong_1.0.0_amd64.deb"
rm -rf "$PKG_DIR"

echo "[4/4] Tao script cai dat tu dong ho tro don dep ban cu (install.sh)..."
cat << 'INSTALL_SH_EOF' > "$DIST_DIR/install.sh"
#!/bin/bash
set -e

echo "=========================================================="
echo "    CAI DAT UNG DUNG MXH TU DONG CHO UBUNTU / DEBIAN     "
echo "=========================================================="

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_FILE="$CURRENT_DIR/mxh-tu-dong_1.0.0_amd64.deb"

if [ ! -f "$DEB_FILE" ]; then
    echo "Loi: Khong tim thay file $DEB_FILE"
    exit 1
fi

echo "[1/3] Don dep phien ban cu va dong tien trinh cu neu co..."
pkill -9 -f "/opt/mxh-tu-dong/agent_mxh_auto" 2>/dev/null || true
pkill -9 -f "agent_mxh_auto" 2>/dev/null || true

# Go bo bang apt/dpkg neu package da cai dat
if dpkg -s mxh-tu-dong >/dev/null 2>&1; then
    echo "Dang go bo package debian cu..."
    sudo dpkg -P mxh-tu-dong || true
fi

# Xoa thu muc cai dat cu va symlink neu ton tai
echo "Dang xoa cac file cai dat cu con sot..."
sudo rm -rf /opt/mxh-tu-dong
sudo rm -f /usr/bin/mxh-tu-dong
sudo rm -f /usr/share/applications/mxh-tu-dong.desktop
sudo rm -f /usr/share/icons/hicolor/*/apps/mxh-tu-dong.*
sudo rm -f /usr/share/icons/hicolor/*/apps/agent.mxh.auto.*
sudo rm -f /usr/share/icons/hicolor/*/apps/agent_mxh_auto.*

# Xoa cac file de lai trong user local neu co
rm -f ~/.local/share/applications/agent.mxh.auto.desktop

echo "[2/3] Tien hanh cai dat ban moi tu goi .deb..."
sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y

# Dong bo ban chay local cho nguoi dung hien tai de phong loi quyen /opt
mkdir -p ~/.local/share/mxh-tu-dong
cp -r /opt/mxh-tu-dong/* ~/.local/share/mxh-tu-dong/ 2>/dev/null || true
mkdir -p ~/.local/bin
cat << 'RUNNER_EOF' > ~/.local/bin/mxh-tu-dong
#!/bin/bash
export GDK_BACKEND=x11
if [ -x "/opt/mxh-tu-dong/agent_mxh_auto" ]; then
    exec /opt/mxh-tu-dong/agent_mxh_auto "$@"
elif [ -x "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" ]; then
    exec "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" "$@"
fi
RUNNER_EOF
chmod +x ~/.local/bin/mxh-tu-dong

mkdir -p ~/.local/share/applications
cat << USER_DESK_EOF > ~/.local/share/applications/mxh-tu-dong.desktop
[Desktop Entry]
Name=Diễn viên MXH
Comment=Diễn viên MXH
Exec=$HOME/.local/bin/mxh-tu-dong %u
Icon=mxh-tu-dong
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
StartupWMClass=agent.mxh.auto
USER_DESK_EOF
chmod +x ~/.local/share/applications/mxh-tu-dong.desktop

echo "[3/3] Lam moi cache icon va desktop entry..."
for s in 16 24 32 48 64 128 256 512; do
    s_clean="${s%,}"
    mkdir -p ~/.local/share/icons/hicolor/${s_clean}x${s_clean}/apps
    cp /usr/share/icons/hicolor/${s_clean}x${s_clean}/apps/mxh-tu-dong.png ~/.local/share/icons/hicolor/${s_clean}x${s_clean}/apps/ 2>/dev/null || true
done
mkdir -p ~/.local/share/pixmaps
cp /usr/share/pixmaps/mxh-tu-dong.png ~/.local/share/pixmaps/ 2>/dev/null || true
cp /usr/share/icons/hicolor/index.theme ~/.local/share/icons/hicolor/index.theme 2>/dev/null || true

sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "=========================================================="
echo " CAI DAT THANH CONG!"
echo " - Duong dan thuc thi: /usr/bin/mxh-tu-dong"
echo " - Hoac mo truc tiep tu Menu Ung dung: 'Diễn viên MXH'"
echo "=========================================================="
INSTALL_SH_EOF
chmod +x "$DIST_DIR/install.sh"

echo "========================================================"
echo " HOAN TAT DONG GOI CHO UBUNTU!"
echo " File cai dat .deb: $DIST_DIR/mxh-tu-dong_1.0.0_amd64.deb"
echo " File script cai:   $DIST_DIR/install.sh"
echo "========================================================"
