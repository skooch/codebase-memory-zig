#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="compare"
MANIFEST_PATH="$ROOT_DIR/testdata/bench/manifest.json"
REPORT_DIR="$ROOT_DIR/.benchmark_reports"
POSITIONAL_ARGS=()
FORWARD_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --zig-only)
      MODE="zig-only"
      shift
      ;;
    --manifest)
      MANIFEST_PATH="${2:?--manifest requires a path}"
      shift 2
      ;;
    --report-dir)
      REPORT_DIR="${2:?--report-dir requires a path}"
      shift 2
      ;;
    --repo-id)
      FORWARD_ARGS+=("$1" "${2:?--repo-id requires a value}")
      shift 2
      ;;
    --source-cache-dir)
      FORWARD_ARGS+=("$1" "${2:?--source-cache-dir requires a value}")
      shift 2
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        FORWARD_ARGS+=("$1")
        shift
      done
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL_ARGS[@]}" -gt 0 ]; then
  MANIFEST_PATH="${POSITIONAL_ARGS[0]}"
fi

if [ "${#POSITIONAL_ARGS[@]}" -gt 1 ]; then
  REPORT_DIR="${POSITIONAL_ARGS[1]}"
fi

if [ "${#POSITIONAL_ARGS[@]}" -gt 2 ]; then
  idx=2
  while [ "$idx" -lt "${#POSITIONAL_ARGS[@]}" ]; do
    FORWARD_ARGS+=("${POSITIONAL_ARGS[$idx]}")
    idx=$((idx + 1))
  done
fi

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

PY_ARGS=(
  --manifest "$MANIFEST_PATH"
  --root "$ROOT_DIR"
  --zig-bin "$ZIG_BIN"
  --report-dir "$REPORT_DIR"
)

if [ "$MODE" = "zig-only" ]; then
  PY_ARGS+=(--zig-only)
else
  PY_ARGS+=(--c-bin "$C_BIN")
fi

if [ "${#FORWARD_ARGS[@]}" -gt 0 ]; then
  PY_ARGS+=("${FORWARD_ARGS[@]}")
fi

python3 "$SCRIPT_DIR/run_benchmark_suite.py" "${PY_ARGS[@]}"
