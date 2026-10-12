#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist-flutter"

mkdir -p "$DIST_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "========================================================"
  echo "[LỖI] Không thể build mục tiêu macOS trên hệ điều hành $(uname -s)."
  echo "Flutter và Xcode chỉ hỗ trợ biên dịch ứng dụng macOS khi chạy trực tiếp trên máy Mac (macOS)."
  echo "Vui lòng clone mã nguồn về máy Mac và chạy script này."
  echo "========================================================"
  exit 1
fi

echo "=== Building Flutter macOS Release ==="
cd "$PROJECT_DIR"
flutter build macos --release

echo "=== Packaging macOS App Bundle ==="
cd "$PROJECT_DIR/build/macos/Build/Products/Release"
zip -r -y "$DIST_DIR/MXH-Tu-Dong-macOS-Universal.zip" "agent_mxh_auto.app"

echo "=== [THÀNH CÔNG] Gói cài đặt macOS đã được tạo tại: $DIST_DIR/MXH-Tu-Dong-macOS-Universal.zip ==="
