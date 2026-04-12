#!/usr/bin/env bash
# fetch_grammars.sh: Download tree-sitter grammar sources into vendored/grammars/
# and tree-sitter headers into vendored/tree_sitter/.
#
# Run after first clone or pass --force to re-fetch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GRAMMAR_DIR="$ROOT_DIR/vendored/grammars"
TS_HEADER_DIR="$ROOT_DIR/vendored/tree_sitter"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

if [[ "$FORCE" == false ]] && [[ -f "$GRAMMAR_DIR/rust/parser.c" ]]; then
    echo "Grammars already present. Use --force to re-fetch."
    exit 0
fi

# Pinned versions - update these when upgrading grammars
declare -A GRAMMAR_REPOS=(
    [rust]="https://github.com/tree-sitter/tree-sitter-rust"
    [python]="https://github.com/tree-sitter/tree-sitter-python"
    [javascript]="https://github.com/tree-sitter/tree-sitter-javascript"
    [typescript]="https://github.com/tree-sitter/tree-sitter-typescript"
    [tsx]="https://github.com/tree-sitter/tree-sitter-typescript"
    [zig]="https://github.com/tree-sitter-grammars/tree-sitter-zig"
)

declare -A GRAMMAR_TAGS=(
    [rust]="v0.24.2"
    [python]="v0.25.0"
    [javascript]="v0.25.0"
    [typescript]="v0.23.2"
    [tsx]="v0.23.2"
    [zig]="v1.1.2"
)

# Subdirectory within repo where src/ lives (for monorepos)
declare -A GRAMMAR_SUBDIRS=(
    [typescript]="typescript"
    [tsx]="tsx"
)

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fetch_grammar() {
    local name="$1"
    local repo="${GRAMMAR_REPOS[$name]}"
    local tag="${GRAMMAR_TAGS[$name]}"
    local subdir="${GRAMMAR_SUBDIRS[$name]:-}"
    local dest="$GRAMMAR_DIR/$name"
    local clone_dir="$TMPDIR/$name"

    echo "Fetching $name ($tag)..."
    git clone --depth 1 --branch "$tag" "$repo" "$clone_dir" 2>/dev/null

    local src_dir="$clone_dir/src"
    if [[ -n "$subdir" ]]; then
        src_dir="$clone_dir/$subdir/src"
    fi

    if [[ ! -f "$src_dir/parser.c" ]]; then
        echo "ERROR: $src_dir/parser.c not found" >&2
        return 1
    fi

    mkdir -p "$dest"
    cp "$src_dir/parser.c" "$dest/"

    if [[ -f "$src_dir/scanner.c" ]]; then
        cp "$src_dir/scanner.c" "$dest/"
    fi

    # tree_sitter headers bundled with grammars
    if [[ -d "$src_dir/tree_sitter" ]]; then
        cp -r "$src_dir/tree_sitter" "$dest/tree_sitter"
    fi

    # For typescript monorepo: patch scanner.c to use local _common_scanner.h
    if [[ -n "$subdir" ]] && [[ -f "$clone_dir/common/scanner.h" ]]; then
        cp "$clone_dir/common/scanner.h" "$dest/_common_scanner.h"
        sed -i.bak 's|#include "../../common/scanner.h"|#include "_common_scanner.h"|' "$dest/scanner.c"
        rm -f "$dest/scanner.c.bak"
    fi
}

# Clean existing if force
if [[ "$FORCE" == true ]]; then
    rm -rf "$GRAMMAR_DIR" "$TS_HEADER_DIR"
fi

# typescript and tsx share a repo but are cloned separately for simplicity
for lang in rust python javascript typescript tsx zig; do
    fetch_grammar "$lang"
done

# Collect tree_sitter headers from the first grammar that has them
echo "Collecting tree-sitter headers..."
mkdir -p "$TS_HEADER_DIR/tree_sitter"
cp "$GRAMMAR_DIR/rust/tree_sitter/"*.h "$TS_HEADER_DIR/tree_sitter/"

echo "Done. Grammars in $GRAMMAR_DIR, headers in $TS_HEADER_DIR"
