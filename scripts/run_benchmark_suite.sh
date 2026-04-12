#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST_PATH="${1:-$ROOT_DIR/testdata/bench/manifest.json}"
REPORT_DIR="${2:-$ROOT_DIR/.benchmark_reports}"

C_BIN_DEFAULT="$ROOT_DIR/../codebase-memory-mcp/build/c/codebase-memory-mcp"
if [ ! -x "$C_BIN_DEFAULT" ]; then
  ALT_C_BIN_DEFAULT="$ROOT_DIR/../../codebase-memory-mcp/build/c/codebase-memory-mcp"
  if [ -x "$ALT_C_BIN_DEFAULT" ]; then
    C_BIN_DEFAULT="$ALT_C_BIN_DEFAULT"
  fi
fi
C_BIN="${CODEBASE_MEMORY_C_BIN:-$C_BIN_DEFAULT}"

if [ -n "${CODEBASE_MEMORY_ZIG_BIN:-}" ]; then
  ZIG_BIN="$CODEBASE_MEMORY_ZIG_BIN"
else
  ZIG_CACHE_DIR="${CODEBASE_MEMORY_ZIG_CACHE_DIR:-$ROOT_DIR/.zig-cache-bench}"
  ZIG_GLOBAL_CACHE_DIR="${CODEBASE_MEMORY_ZIG_GLOBAL_CACHE_DIR:-$ROOT_DIR/.zig-global-cache-bench}"
  ZIG_PREFIX_DIR="${CODEBASE_MEMORY_ZIG_PREFIX:-$ROOT_DIR/.zig-prefix-bench}"
  zig build -Doptimize=ReleaseFast --cache-dir "$ZIG_CACHE_DIR" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" --prefix "$ZIG_PREFIX_DIR" >/dev/null
  ZIG_BIN="$ZIG_PREFIX_DIR/bin/cbm"
fi

mkdir -p "$REPORT_DIR"

python3 "$SCRIPT_DIR/run_benchmark_suite.py" \
  --manifest "$MANIFEST_PATH" \
  --root "$ROOT_DIR" \
  --zig-bin "$ZIG_BIN" \
  --c-bin "$C_BIN" \
  --report-dir "$REPORT_DIR"
