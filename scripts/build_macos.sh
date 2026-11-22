#!/bin/bash

# build_macos.sh
# 构建 macOS 应用并自动同步版本号，支持分别打包 arm64 与 x86_64
# 用法: ./scripts/build_macos.sh [--arch arm64|x86_64|all] [flutter build 参数...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TARGET_ARCH="${MACOS_BUILD_ARCH:-all}"
FLUTTER_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            TARGET_ARCH="${2:-}"
            shift 2
            ;;
        --arch=*)
            TARGET_ARCH="${1#*=}"
            shift
            ;;
        *)
            FLUTTER_ARGS+=("$1")
            shift
            ;;
    esac
done

case "$TARGET_ARCH" in
    arm64) ARCH_LIST=("arm64") ;;
    x86_64) ARCH_LIST=("x86_64") ;;
    all) ARCH_LIST=("arm64" "x86_64") ;;
    *)
        echo "❌ 不支持的 macOS 架构: $TARGET_ARCH (可选: arm64, x86_64, all)"
        exit 1
        ;;
esac

APP_INFO_XCCONFIG="$PROJECT_ROOT/macos/Runner/Configs/AppInfo.xcconfig"
if [ ! -f "$APP_INFO_XCCONFIG" ]; then
    echo "❌ 未找到 AppInfo.xcconfig: $APP_INFO_XCCONFIG"
    exit 1
fi

APP_INFO_BACKUP="$(mktemp /private/tmp/appinfo-xcconfig.XXXXXX)"
cp "$APP_INFO_XCCONFIG" "$APP_INFO_BACKUP"
WAS_ARM64_ONLY=0
if "$FLUTTER_BIN" config --list 2>/dev/null | grep -q "enable-macos-arm64-only: true"; then
    WAS_ARM64_ONLY=1
fi

restore_app_info() {
    if [ -f "$APP_INFO_BACKUP" ]; then
        cp "$APP_INFO_BACKUP" "$APP_INFO_XCCONFIG"
        rm -f "$APP_INFO_BACKUP"
    fi
    if [ "$WAS_ARM64_ONLY" -eq 1 ]; then
        "$FLUTTER_BIN" config --enable-macos-arm64-only >/dev/null 2>&1 || true
    fi
}
trap restore_app_info EXIT

set_xcconfig_arch() {
    local arch="$1"
    if grep -q '^ARCHS =' "$APP_INFO_XCCONFIG"; then
        sed -i '' "s/^ARCHS = .*/ARCHS = ${arch};/" "$APP_INFO_XCCONFIG"
    else
        printf '\nARCHS = %s;\n' "$arch" >> "$APP_INFO_XCCONFIG"
    fi
}

echo "=== 同步 macOS 版本号 ==="
"$SCRIPT_DIR/sync_macos_version.sh"

APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/CountDownTodo.app"
ZIP_DIR="$PROJECT_ROOT/build/macos"
mkdir -p "$ZIP_DIR"

for arch in "${ARCH_LIST[@]}"; do
    echo ""
    echo "=== 构建 macOS ($arch) 应用 ==="
    if [ "$arch" = "x86_64" ] && [ "$WAS_ARM64_ONLY" -eq 1 ]; then
        "$FLUTTER_BIN" config --no-enable-macos-arm64-only >/dev/null
    fi
    set_xcconfig_arch "$arch"
    cd "$PROJECT_ROOT"
    "$FLUTTER_BIN" build macos --dart-define=countdown.disable_windows_island=true "${FLUTTER_ARGS[@]}"

    echo ""
    echo "=== 打包 macOS ($arch) 应用为 ZIP ==="
    ZIP_PATH="$ZIP_DIR/CountDownTodo-macOS-${arch}.zip"
    if [ -d "$APP_PATH" ]; then
        if command -v lipo >/dev/null 2>&1; then
            BUILT_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/CountDownTodo" 2>/dev/null || true)"
            echo "🔍 产物架构: ${BUILT_ARCHS:-unknown}"
            if [[ -n "$BUILT_ARCHS" && "$BUILT_ARCHS" != *"$arch"* ]]; then
                echo "❌ 构建产物不包含目标架构 $arch (实际: $BUILT_ARCHS)"
                exit 1
            fi
        fi
        rm -f "$ZIP_PATH"
        cd "$PROJECT_ROOT/build/macos/Build/Products/Release"
        zip -r -y "$ZIP_PATH" "CountDownTodo.app"
        echo "✅ 已生成: $ZIP_PATH"
        echo "📦 文件大小: $(du -h "$ZIP_PATH" | cut -f1)"
    else
        echo "❌ 未找到 .app 文件: $APP_PATH"
        exit 1
    fi
done
