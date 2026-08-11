#!/bin/bash

# sync_macos_version.sh
# 同步 pubspec.yaml 版本号到 macOS 项目配置
# 用法: ./scripts/sync_macos_version.sh

set -e

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 从 pubspec.yaml 读取版本号
PUBSPEC_FILE="$PROJECT_ROOT/pubspec.yaml"
if [ ! -f "$PUBSPEC_FILE" ]; then
    echo "错误: 找不到 pubspec.yaml"
    exit 1
fi

VERSION=$(grep "^version:" "$PUBSPEC_FILE" | sed 's/version: //' | tr -d '[:space:]')
if [ -z "$VERSION" ]; then
    echo "错误: 无法从 pubspec.yaml 读取版本号"
    exit 1
fi

echo "pubspec.yaml 版本号: $VERSION"

# 更新 project.pbxproj 中的版本号
PBXPROJ_FILE="$PROJECT_ROOT/macos/Runner.xcodeproj/project.pbxproj"
if [ ! -f "$PBXPROJ_FILE" ]; then
    echo "错误: 找不到 project.pbxproj"
    exit 1
fi

# 备份原文件；发布脚本可将临时备份放到临时目录，避免污染工作区
BACKUP_DIR="${MACOS_VERSION_BACKUP_DIR:-$(dirname "$PBXPROJ_FILE")}"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/project.pbxproj.backup"
cp "$PBXPROJ_FILE" "$BACKUP_FILE"

# 更新所有 CURRENT_PROJECT_VERSION 和 MARKETING_VERSION
# 使用 sed 替换所有匹配的行
sed -i '' \
    -e "s/CURRENT_PROJECT_VERSION = [0-9]*\.[0-9]*\.[0-9]*/CURRENT_PROJECT_VERSION = $VERSION/g" \
    -e "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*/MARKETING_VERSION = $VERSION/g" \
    "$PBXPROJ_FILE"

# 验证更新
echo "更新后的版本号:"
grep -n "CURRENT_PROJECT_VERSION\|MARKETING_VERSION" "$PBXPROJ_FILE" | head -10

echo ""
echo "版本同步完成！"
echo "备份文件: $BACKUP_FILE"
