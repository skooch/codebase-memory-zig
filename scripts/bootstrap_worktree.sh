#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRIMARY_ROOT_DEFAULT="$ROOT_DIR/../codebase-memory-zig"
PRIMARY_ROOT="${1:-$PRIMARY_ROOT_DEFAULT}"

copy_if_missing() {
  local rel_path="$1"
  local src="$PRIMARY_ROOT/$rel_path"
  local dst="$ROOT_DIR/$rel_path"

  if [ -e "$dst" ]; then
    return 0
  fi
  if [ ! -e "$src" ]; then
    echo "missing source path: $src" >&2
    return 1
  fi

  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
}

copy_if_missing "vendored/grammars"
copy_if_missing "vendored/tree_sitter"

echo "worktree bootstrap complete"
