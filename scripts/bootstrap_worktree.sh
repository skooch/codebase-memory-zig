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

copy_children_if_missing() {
  local rel_path="$1"
  local src_dir="$PRIMARY_ROOT/$rel_path"
  local dst_dir="$ROOT_DIR/$rel_path"

  if [ ! -d "$src_dir" ]; then
    echo "missing source path: $src_dir" >&2
    return 1
  fi

  mkdir -p "$dst_dir"

  local src_child=""
  for src_child in "$src_dir"/*; do
    if [ ! -e "$src_child" ]; then
      continue
    fi

    local child_name
    child_name="$(basename "$src_child")"
    if [ -e "$dst_dir/$child_name" ]; then
      continue
    fi

    cp -R "$src_child" "$dst_dir/$child_name"
  done
}

copy_children_if_missing "vendored/grammars"
copy_children_if_missing "vendored/tree_sitter"

echo "worktree bootstrap complete"
