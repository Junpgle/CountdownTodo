#!/bin/bash

# deploy_web_beta.sh
# Build and deploy the Flutter Web beta to an isolated Cloudflare Pages project.
# Usage:
#   ./scripts/deploy_web_beta.sh
#   ./scripts/deploy_web_beta.sh --skip-build
#   ./scripts/deploy_web_beta.sh --project countdowntodo-beta --branch main

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PAGES_PROJECT="countdowntodo-beta"
PAGES_BRANCH="main"
COMMIT_MESSAGE="Deploy Flutter Web beta"
SKIP_BUILD=0
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
WRANGLER_CMD="${WRANGLER_CMD:-npx --yes wrangler@latest}"

usage() {
    cat <<EOF
Usage: ./scripts/deploy_web_beta.sh [options]

Options:
  --skip-build            Deploy existing build/web without rebuilding.
  --project <name>        Cloudflare Pages project. Default: countdowntodo-beta.
  --branch <name>         Cloudflare Pages branch. Default: main.
  --message <text>        Deployment message. Default: "Deploy Flutter Web beta".
  -h, --help              Show this help.

Environment:
  FLUTTER_BIN             Flutter command path. Default: flutter.
  WRANGLER_CMD            Wrangler command. Default: npx --yes wrangler@latest.

This script intentionally deploys to countdowntodo-beta by default.
Do not use the old production project name "countdowntodo" for beta builds.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --project)
            PAGES_PROJECT="${2:-}"
            shift 2
            ;;
        --branch)
            PAGES_BRANCH="${2:-}"
            shift 2
            ;;
        --message)
            COMMIT_MESSAGE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "错误: 未知参数 $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$PAGES_PROJECT" || -z "$PAGES_BRANCH" ]]; then
    echo "错误: Pages 项目名和分支不能为空"
    exit 1
fi

if [[ "$PAGES_PROJECT" == "countdowntodo" ]]; then
    echo "错误: 不能把 beta 版部署到旧版正式项目 countdowntodo"
    echo "请使用独立项目 countdowntodo-beta。"
    exit 1
fi

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
    echo "错误: 找不到 Flutter 命令: $FLUTTER_BIN"
    echo "可用 FLUTTER_BIN=/path/to/flutter 指定。"
    exit 1
fi

if ! command -v npx >/dev/null 2>&1 && [[ "$WRANGLER_CMD" == npx* ]]; then
    echo "错误: 找不到 npx，无法运行 Wrangler。"
    exit 1
fi

cd "$PROJECT_ROOT"

echo "=== CountDownTodo Flutter Web Beta Deploy ==="
echo "项目目录: $PROJECT_ROOT"
echo "Pages 项目: $PAGES_PROJECT"
echo "Pages 分支: $PAGES_BRANCH"
echo ""

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "=== 构建 Flutter Web release ==="
    "$FLUTTER_BIN" build web --release --no-wasm-dry-run
else
    echo "=== 跳过构建，使用现有 build/web ==="
fi

if [[ ! -d "$PROJECT_ROOT/build/web" ]]; then
    echo "错误: 找不到 build/web，请先构建 Web 产物。"
    exit 1
fi

echo ""
echo "=== 检查 Wrangler 登录状态 ==="
if ! $WRANGLER_CMD whoami >/dev/null 2>&1; then
    echo "错误: Wrangler 未登录或 token 已失效。"
    echo "请先运行:"
    echo "  npx --yes wrangler@latest login --scopes account:read --scopes user:read --scopes pages:write"
    exit 1
fi

COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo manual)"

echo ""
echo "=== 部署到 Cloudflare Pages ==="
$WRANGLER_CMD pages deploy build/web \
    --project-name "$PAGES_PROJECT" \
    --branch "$PAGES_BRANCH" \
    --commit-hash "$COMMIT_HASH" \
    --commit-message "$COMMIT_MESSAGE" \
    --commit-dirty=true

echo ""
echo "✅ 部署完成"
echo "Beta 地址: https://${PAGES_PROJECT}.pages.dev"
