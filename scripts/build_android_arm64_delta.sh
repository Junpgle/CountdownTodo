#!/usr/bin/env bash

# Generate the arm64-v8a delta used by the next release.
#
# The baseline APK URL is intentionally fixed to the previous public release. The
# client does not download this file during an update; it uses the APK already
# installed on the device. This URL is only needed by the release process to
# generate the patch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

BASE_APK_URL="https://foruda.gitee.com/attach_file/1785852761107128667/app-arm64-v8a-release.apk?token=76809a89707124ac20dfd316cc140b39&ts=1785853497&attname=app-arm64-v8a-release.apk"

# The manifest's current version is the latest public release and therefore
# the base for the next APK passed to this script.
BASE_VERSION="$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)

print(str(manifest.get("version_name", "")).strip())
' "$PROJECT_ROOT/update_manifest.json")"

BASE_APK_FALLBACK_URL="$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)

print(
    manifest.get("update_info", {})
    .get("android_arch_packages", {})
    .get("arm64-v8a", "")
)
' "$PROJECT_ROOT/update_manifest.json")"

NEW_APK_PATH="${1:-$PROJECT_ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk}"
NEW_VERSION="${2:-$(sed -n 's/^version: *//p' "$PROJECT_ROOT/pubspec.yaml" | head -n 1 | tr -d '[:space:]' | sed 's/+.*//')}"
OUTPUT_DIR="${3:-$PROJECT_ROOT/build/android-delta}"

if [[ ! -f "$NEW_APK_PATH" ]]; then
  echo "❌ 未找到新版 arm64-v8a APK: $NEW_APK_PATH" >&2
  exit 1
fi

if [[ -z "$NEW_VERSION" ]]; then
  echo "❌ 无法从 pubspec.yaml 读取新版版本号" >&2
  exit 1
fi

if [[ -z "$BASE_VERSION" ]]; then
  echo "❌ 无法从 update_manifest.json 的 changelog_history 读取上一个版本" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d /private/tmp/countdown-todo-old-apk.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

OLD_APK_PATH="$TEMP_DIR/app-arm64-v8a-release.apk"
PATCH_PATH="$OUTPUT_DIR/app-arm64-v8a-${BASE_VERSION}_to_${NEW_VERSION}.patch"

echo "=== 下载基线 APK v$BASE_VERSION ==="
if ! curl --fail --location --retry 3 --output "$OLD_APK_PATH" "$BASE_APK_URL"; then
  if [[ -z "$BASE_APK_FALLBACK_URL" ]]; then
    echo "❌ 临时基线地址失效，且 update_manifest.json 没有公开 arm64-v8a 地址" >&2
    exit 1
  fi
  echo "⚠️ 临时基线地址不可用，改用 update_manifest.json 中的公开地址"
  curl --fail --location --retry 3 --output "$OLD_APK_PATH" "$BASE_APK_FALLBACK_URL"
fi

echo "=== 生成 arm64-v8a 差分包 v$BASE_VERSION -> v$NEW_VERSION ==="
DELTA_COMMAND=(
  python3 "$PROJECT_ROOT/scripts/android_delta.py"
  "$OLD_APK_PATH"
  "$NEW_APK_PATH"
  "$PATCH_PATH"
  --from-version "$BASE_VERSION"
  --to-version "$NEW_VERSION"
)
if [[ -n "${DELTA_METADATA_PATH:-}" ]]; then
  "${DELTA_COMMAND[@]}" > "$DELTA_METADATA_PATH"
  cat "$DELTA_METADATA_PATH"
else
  "${DELTA_COMMAND[@]}"
fi

echo "✅ 差分包已生成: $PATCH_PATH"
echo "请将上面 JSON 中的 patch_url 写入 update_manifest.json。"
