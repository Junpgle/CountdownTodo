#!/usr/bin/env bash

# Generate the arm64-v8a delta used by the next release.
#
# The client does not download this file during an update; it uses the APK
# already installed on the device. This URL is only needed by the release
# process to generate the patch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# The manifest's current version is the latest public release and therefore
# the base for the next APK passed to this script.
BASE_VERSION="$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)

print(str(manifest.get("version_name", "")).strip())
' "$PROJECT_ROOT/update_manifest.json")"

# Prefer a versioned public release URL. The mutable Gitee "latestrelease" URL
# can point to the target APK after publishing and must never silently become
# the delta base. Override this with BASE_APK_URL when the public baseline is
# hosted elsewhere. BASE_APK_FALLBACK_URL is intentionally opt-in for the same
# reason.
BASE_APK_URL="${BASE_APK_URL:-https://github.com/Junpgle/CountdownTodo/releases/download/v${BASE_VERSION}/app-arm64-v8a-release.apk}"
BASE_APK_FALLBACK_URL="${BASE_APK_FALLBACK_URL:-}"
BASE_APK_SHA256="${BASE_APK_SHA256:-}"

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

sha256_file() {
  python3 - "$1" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as stream:
    while chunk := stream.read(1024 * 1024):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

TEMP_DIR="$(mktemp -d /private/tmp/countdown-todo-old-apk.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

OLD_APK_PATH="$TEMP_DIR/app-arm64-v8a-release.apk"
PATCH_PATH="$OUTPUT_DIR/app-arm64-v8a-${BASE_VERSION}_to_${NEW_VERSION}.patch"

echo "=== 下载基线 APK v$BASE_VERSION ==="
if ! curl --fail --location --retry 3 --output "$OLD_APK_PATH" "$BASE_APK_URL"; then
  if [[ -z "$BASE_APK_FALLBACK_URL" ]]; then
    echo "❌ 基线 APK 地址失效: $BASE_APK_URL" >&2
    exit 1
  fi
  echo "⚠️ 基线地址不可用，改用显式提供的备用地址"
  curl --fail --location --retry 3 --output "$OLD_APK_PATH" "$BASE_APK_FALLBACK_URL"
fi

OLD_APK_SHA256="$(sha256_file "$OLD_APK_PATH")"
NEW_APK_SHA256="$(sha256_file "$NEW_APK_PATH")"
echo "基线 APK SHA-256: $OLD_APK_SHA256"
echo "目标 APK SHA-256: $NEW_APK_SHA256"
if [[ -n "$BASE_APK_SHA256" && "$OLD_APK_SHA256" != "$BASE_APK_SHA256" ]]; then
  echo "❌ 基线 APK SHA-256 不匹配，拒绝生成差分包" >&2
  echo "   期望: $BASE_APK_SHA256" >&2
  echo "   实际: $OLD_APK_SHA256" >&2
  exit 1
fi
if [[ "$OLD_APK_SHA256" == "$NEW_APK_SHA256" ]]; then
  echo "❌ 基线 APK 与目标 APK 完全相同，拒绝生成差分包" >&2
  exit 1
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
