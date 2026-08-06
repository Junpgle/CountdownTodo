#!/usr/bin/env bash

# Build all release artifacts locally and collect the files that should be
# selected together when uploading a GitHub/Gitee release manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_ROOT="$PROJECT_ROOT/build"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="${RELEASE_OUTPUT_DIR:-}"
WEB_PROJECT="${WEB_PROJECT:-countdowntodo-beta}"
WEB_BRANCH="${WEB_BRANCH:-main}"
WEB_MESSAGE="${WEB_MESSAGE:-Deploy Flutter Web beta}"

SKIP_BUILD=0
SKIP_WEB=0
SKIP_DELTA=0
DRY_RUN=0

usage() {
  cat <<'EOF'
用法:
  ./scripts/release_all.sh [选项]

默认流程:
  1. 调用 build_macos.sh 构建 macOS ZIP
  2. 调用 deploy_web_beta.sh 构建并发布 Web
  3. 构建 Android 的 arm64-v8a、armeabi-v7a、x86_64 三个 APK
  4. 生成 arm64-v8a Android 差分包
  5. 将 macOS ZIP、三个 APK、差分包复制到同一个版本目录

选项:
  --output-dir <dir>       产物目录，默认 build/release-assets/v<版本>
  --web-project <name>     Cloudflare Pages 项目，默认 countdowntodo-beta
  --web-branch <name>      Cloudflare Pages 分支，默认 main
  --web-message <text>     Web 部署消息
  --skip-build             不重新构建，直接使用已有产物并归集
  --skip-web               不调用 deploy_web_beta.sh
  --skip-delta             不生成差分包
  --dry-run                只显示版本和目标目录，不执行构建
  -h, --help               显示帮助

环境变量:
  FLUTTER_BIN              Flutter 命令路径，默认 flutter
  RELEASE_OUTPUT_DIR       默认产物目录
  WEB_PROJECT / WEB_BRANCH / WEB_MESSAGE

完成后可直接全选产物目录中的文件，上传到 GitHub/Gitee Release。
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ 找不到命令: $1" >&2
    exit 1
  fi
}

read_pubspec_version() {
  python3 - "$PROJECT_ROOT/pubspec.yaml" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"(?m)^version:\s*([^\s]+)", text)
if not match:
    raise SystemExit("无法从 pubspec.yaml 读取 version")
print(match.group(1).split("+")[0])
PY
}

read_manifest_version() {
  python3 - "$PROJECT_ROOT/update_manifest.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    version = json.load(stream).get("version_name", "")
if not version:
    raise SystemExit("无法从 update_manifest.json 读取基线版本")
print(version)
PY
}

find_apk() {
  local name="$1"
  local candidate
  for candidate in \
    "$BUILD_ROOT/app/outputs/flutter-apk/$name" \
    "$BUILD_ROOT/app/outputs/apk/release/$name"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "❌ 找不到 Android 产物: $name" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --web-project)
      WEB_PROJECT="${2:-}"
      shift 2
      ;;
    --web-branch)
      WEB_BRANCH="${2:-}"
      shift 2
      ;;
    --web-message)
      WEB_MESSAGE="${2:-}"
      shift 2
      ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-web) SKIP_WEB=1; shift ;;
    --skip-delta) SKIP_DELTA=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ 未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

require_command python3
VERSION="$(read_pubspec_version)"
BASE_VERSION="$(read_manifest_version)"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$BUILD_ROOT/release-assets/v$VERSION"
elif [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"
fi

echo "版本: $VERSION"
echo "Android 差分基线: $BASE_VERSION"
echo "产物目录: $OUTPUT_DIR"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "✅ dry-run 完成"
  exit 0
fi

require_command "$FLUTTER_BIN"
require_command bash
require_command cp
require_command mkdir

TEMP_DIR="$(mktemp -d /private/tmp/countdown-todo-release.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  cd "$PROJECT_ROOT"
  echo "=== Flutter 依赖 ==="
  "$FLUTTER_BIN" pub get

  echo "=== 构建 Android 三 ABI APK ==="
  "$FLUTTER_BIN" build apk --release

  echo "=== 构建 macOS ==="
  MACOS_VERSION_BACKUP_DIR="$TEMP_DIR/macos-backup" \
    FLUTTER_BIN="$FLUTTER_BIN" \
    bash "$SCRIPT_DIR/build_macos.sh"

  if [[ "$SKIP_WEB" -eq 0 ]]; then
    echo "=== 构建并发布 Web ==="
    FLUTTER_BIN="$FLUTTER_BIN" \
      bash "$SCRIPT_DIR/deploy_web_beta.sh" \
      --project "$WEB_PROJECT" \
      --branch "$WEB_BRANCH" \
      --message "$WEB_MESSAGE"
  else
    echo "=== 跳过 Web 构建和发布 ==="
  fi
else
  echo "=== 跳过构建，使用已有产物 ==="
fi

ANDROID_ARM64_APK="$(find_apk app-arm64-v8a-release.apk)"
ANDROID_ARMV7_APK="$(find_apk app-armeabi-v7a-release.apk)"
ANDROID_X86_64_APK="$(find_apk app-x86_64-release.apk)"
MACOS_ZIP="$BUILD_ROOT/macos/CountDownTodo-macOS-arm64.zip"
[[ -f "$MACOS_ZIP" ]] || { echo "❌ 找不到 macOS ZIP: $MACOS_ZIP" >&2; exit 1; }

DELTA_PATH=""
DELTA_METADATA="$TEMP_DIR/delta_metadata.json"
if [[ "$SKIP_DELTA" -eq 0 ]]; then
  if [[ "$BASE_VERSION" == "$VERSION" ]]; then
    echo "❌ 差分基线版本与当前版本相同: $BASE_VERSION" >&2
    exit 1
  fi
  echo "=== 生成 arm64-v8a 差分包 ==="
  DELTA_METADATA_PATH="$DELTA_METADATA" \
    bash "$SCRIPT_DIR/build_android_arm64_delta.sh" \
    "$ANDROID_ARM64_APK" "$VERSION" "$BUILD_ROOT/android-delta"
  DELTA_PATH="$BUILD_ROOT/android-delta/app-arm64-v8a-${BASE_VERSION}_to_${VERSION}.patch"
  [[ -f "$DELTA_PATH" ]] || { echo "❌ 找不到差分包: $DELTA_PATH" >&2; exit 1; }
else
  echo "=== 跳过差分包 ==="
fi

mkdir -p "$OUTPUT_DIR"
cp "$MACOS_ZIP" "$OUTPUT_DIR/CountDownTodo-macOS-arm64.zip"
cp "$ANDROID_ARM64_APK" "$OUTPUT_DIR/app-arm64-v8a-release.apk"
cp "$ANDROID_ARMV7_APK" "$OUTPUT_DIR/app-armeabi-v7a-release.apk"
cp "$ANDROID_X86_64_APK" "$OUTPUT_DIR/app-x86_64-release.apk"
if [[ -n "$DELTA_PATH" ]]; then
  cp "$DELTA_PATH" "$OUTPUT_DIR/$(basename "$DELTA_PATH")"
fi

echo ""
echo "✅ 产物归集完成，可直接全选以下目录上传:"
echo "$OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -print | sort
if [[ "$SKIP_WEB" -eq 0 && "$SKIP_BUILD" -eq 0 ]]; then
  echo "Web 已由 deploy_web_beta.sh 构建并发布。"
fi
