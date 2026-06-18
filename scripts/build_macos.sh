#!/bin/bash

# build_macos.sh
# 构建 macOS 应用并自动同步版本号
# 用法: ./scripts/build_macos.sh [flutter build 参数...]

set -e

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== 同步 macOS 版本号 ==="
"$SCRIPT_DIR/sync_macos_version.sh"

echo ""
echo "=== 构建 macOS 应用 ==="
cd "$PROJECT_ROOT"
flutter build macos "$@"

echo ""
echo "=== 打包 macOS 应用为 ZIP ==="
APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/CountDownTodo.app"
ZIP_DIR="$PROJECT_ROOT/build/macos"
ZIP_PATH="$ZIP_DIR/CountDownTodo-macOS-arm64.zip"

if [ -d "$APP_PATH" ]; then
    mkdir -p "$ZIP_DIR"
    rm -f "$ZIP_PATH"
    cd "$PROJECT_ROOT/build/macos/Build/Products/Release"
    zip -r -y "$ZIP_PATH" "CountDownTodo.app"
    echo "✅ 已生成: $ZIP_PATH"
    echo "📦 文件大小: $(du -h "$ZIP_PATH" | cut -f1)"
else
    echo "❌ 未找到 .app 文件: $APP_PATH"
    exit 1
fi
