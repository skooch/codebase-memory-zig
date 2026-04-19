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

all_grammars_present() {
    local lang=""
    for lang in go java rust python javascript typescript tsx zig powershell gdscript; do
        if [[ ! -f "$GRAMMAR_DIR/$lang/parser.c" ]]; then
            return 1
        fi
    done
    return 0
}

if [[ "$FORCE" == false ]] && all_grammars_present; then
    echo "Grammars already present. Use --force to re-fetch."
    exit 0
fi

grammar_repo() {
    case "$1" in
        go) echo "https://github.com/tree-sitter/tree-sitter-go" ;;
        java) echo "https://github.com/tree-sitter/tree-sitter-java" ;;
        rust) echo "https://github.com/tree-sitter/tree-sitter-rust" ;;
        python) echo "https://github.com/tree-sitter/tree-sitter-python" ;;
        javascript) echo "https://github.com/tree-sitter/tree-sitter-javascript" ;;
        typescript) echo "https://github.com/tree-sitter/tree-sitter-typescript" ;;
        tsx) echo "https://github.com/tree-sitter/tree-sitter-typescript" ;;
        zig) echo "https://github.com/tree-sitter-grammars/tree-sitter-zig" ;;
        powershell) echo "https://github.com/airbus-cert/tree-sitter-powershell" ;;
        gdscript) echo "https://github.com/PrestonKnopp/tree-sitter-gdscript" ;;
        *)
            echo "ERROR: unsupported grammar $1" >&2
            return 1
            ;;
    esac
}

grammar_tag() {
    case "$1" in
        go) echo "v0.25.0" ;;
        java) echo "v0.23.5" ;;
        rust) echo "v0.24.2" ;;
        python) echo "v0.25.0" ;;
        javascript) echo "v0.25.0" ;;
        typescript) echo "v0.23.2" ;;
        tsx) echo "v0.23.2" ;;
        zig) echo "v1.1.2" ;;
        powershell) echo "v0.26.3" ;;
        gdscript) echo "v6.1.0" ;;
        *)
            echo "ERROR: unsupported grammar $1" >&2
            return 1
            ;;
    esac
}

grammar_subdir() {
    case "$1" in
        typescript) echo "typescript" ;;
        tsx) echo "tsx" ;;
        *) echo "" ;;
    esac
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fetch_grammar() {
    local name="$1"
    local repo
    repo="$(grammar_repo "$name")"
    local tag
    tag="$(grammar_tag "$name")"
    local subdir
    subdir="$(grammar_subdir "$name")"
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
for lang in go java rust python javascript typescript tsx zig powershell gdscript; do
    fetch_grammar "$lang"
done

# Collect tree_sitter headers from the first grammar that has them
echo "Collecting tree-sitter headers..."
mkdir -p "$TS_HEADER_DIR/tree_sitter"
cp "$GRAMMAR_DIR/rust/tree_sitter/"*.h "$TS_HEADER_DIR/tree_sitter/"

echo "Done. Grammars in $GRAMMAR_DIR, headers in $TS_HEADER_DIR"
