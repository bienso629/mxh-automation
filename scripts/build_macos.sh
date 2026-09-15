#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"
DIST_DIR="$ROOT_DIR/dist-flutter"

mkdir -p "$DIST_DIR"

echo "=== Building Flutter macOS Release ==="
cd "$MOBILE_DIR"
flutter build macos --release

echo "=== Packaging macOS App Bundle ==="
cd "$MOBILE_DIR/build/macos/Build/Products/Release"
zip -r -y "$DIST_DIR/tadu-cloud-ai-agent-flutter-macos.zip" "agent_mxh_auto.app"

echo "=== [SUCCESS] macOS package created at: $DIST_DIR/tadu-cloud-ai-agent-flutter-macos.zip ==="
