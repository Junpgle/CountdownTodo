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
