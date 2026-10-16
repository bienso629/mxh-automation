#!/usr/bin/env bash
set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$SOURCE_DIR/build/linux/x64/release/bundle"
INSTALL_DIR="$HOME/.local/share/mxh-tu-dong"
BIN_LINK="$HOME/.local/bin/mxh-tu-dong"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/mxh-tu-dong.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor"

echo "=========================================================="
echo "   CAI DAT UNG DUNG MXH TU DONG (KHONG CAN SUDO)         "
echo "=========================================================="

# 1. Dong cac tien trinh cu neu co
echo "[1/5] Dong tien trinh ung dung cu..."
pkill -9 -f "mxh-tu-dong|agent_mxh_auto" 2>/dev/null || true

# 2. Kiem tra va bien dich release bundle neu chua co
if [ ! -f "$BUNDLE_DIR/agent_mxh_auto" ]; then
    echo "[2/5] Dang bien dich ban Flutter Linux Release..."
    cd "$SOURCE_DIR"
    flutter build linux --release
else
    echo "[2/5] Da co ban Flutter Linux Release san sang."
fi

# 3. Tao thu muc va copy bundle vao ~/.local/share/mxh-tu-dong
echo "[3/5] Cai dat tap tin ung dung vao $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.local/bin"
mkdir -p "$DESKTOP_DIR"

rm -rf "$INSTALL_DIR"/*
cp -r "$BUNDLE_DIR"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/agent_mxh_auto"

# Tao symlink command line
ln -sf "$INSTALL_DIR/agent_mxh_auto" "$BIN_LINK"

# 4. Cai dat icon day du kich thuoc
echo "[4/5] Cai dat bieu tuong ung dung (icon)..."
python3 -c "
import os
from PIL import Image

src = '$SOURCE_DIR/assets/icon.png'
sizes = [16, 24, 32, 48, 64, 128, 256, 512]
base = os.path.expanduser('~/.local/share/icons/hicolor')
im = Image.open(src)
for s in sizes:
    d = os.path.join(base, f'{s}x{s}', 'apps')
    os.makedirs(d, exist_ok=True)
    resized = im.resize((s, s), getattr(Image, 'Resampling', Image).LANCZOS)
    for n in ['mxh-tu-dong', 'agent.mxh.auto', 'agent_mxh_auto']:
        resized.save(os.path.join(d, f'{n}.png'), format='PNG')
"

# 5. Tao desktop entry cho menu ung dung
echo "[5/5] Tao menu khoi chay Desktop..."
cat << DESKTOP_EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=Diễn viên MXH
GenericName=AI Social Media Manager
Comment=Diễn viên MXH
Exec=$INSTALL_DIR/agent_mxh_auto %u
Icon=mxh-tu-dong
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=agent.mxh.auto
DESKTOP_EOF
chmod +x "$DESKTOP_FILE"

# Lam moi cache desktop va icon
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true

echo "=========================================================="
echo " CAI DAT HOAN TAT THANH CONG 100%!"
echo " - Duong dan cai dat: $INSTALL_DIR/agent_mxh_auto"
echo " - Command line:     mxh-tu-dong (hoac $BIN_LINK)"
echo " - Icon & Menu:      Da cap nhat vao Ubuntu App Menu"
echo "=========================================================="
