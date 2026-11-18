#!/usr/bin/env bash

# Backwards-compatible wrapper for arm64-v8a delta generation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build_android_delta.sh" --abi arm64-v8a "$@"
