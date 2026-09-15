#!/usr/bin/env bash
# Script launch_android_device.sh: Khởi động Android Emulator chuẩn Android Studio
# Chạy với HTTP/HTTPS proxy được bridge từ SOCKS5 của chính IP Profile đó.

AVD_NAME="$1"
HTTP_PROXY="$2"
PORT="$3"
DATA_DIR="$4"

if [ -z "$AVD_NAME" ] || [ -z "$HTTP_PROXY" ]; then
    echo "Usage: launch_android_device.sh <avd_name> <http_proxy> [port] [data_dir]"
    exit 1
fi

EMULATOR_BIN="/home/yenai/Android/Sdk/emulator/emulator"
if [ ! -f "$EMULATOR_BIN" ]; then
    echo "Không tìm thấy Android Emulator binary tại $EMULATOR_BIN"
    exit 1
fi

CMD_ARGS=("-avd" "$AVD_NAME" "-http-proxy" "$HTTP_PROXY" "-netdelay" "none" "-netspeed" "full")

if [ -n "$PORT" ]; then
    CMD_ARGS+=("-port" "$PORT")
fi

if [ -n "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    CMD_ARGS+=("-data" "$DATA_DIR/userdata.img" "-read-only")
fi

exec "$EMULATOR_BIN" "${CMD_ARGS[@]}"
