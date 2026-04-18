#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
SKIP_CONFIG=false
FROM_SOURCE=false

usage() {
    cat <<EOF
Usage: scripts/setup.sh [--from-source] [--dir <path>] [--dir=<path>] [--skip-config]

Default behavior installs from the latest packaged release via ./install.sh.
Use --from-source to build the current checkout with zig and install the local binary.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --from-source)
            FROM_SOURCE=true
            shift
            ;;
        --dir)
            [ "$#" -ge 2 ] || die "--dir requires a path"
            INSTALL_DIR="$2"
            shift 2
            ;;
        --dir=*)
            INSTALL_DIR="${1#--dir=}"
            shift
            ;;
        --skip-config)
            SKIP_CONFIG=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

if [ "$FROM_SOURCE" = false ]; then
    install_args=(--dir "$INSTALL_DIR")
    if [ "$SKIP_CONFIG" = true ]; then
        install_args+=(--skip-config)
    fi
    exec "${ROOT_DIR}/install.sh" "${install_args[@]}"
fi

command -v zig >/dev/null 2>&1 || die "zig is required for --from-source"

BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
PREFIX_DIR="${BUILD_ROOT}/prefix"

(
    cd "$ROOT_DIR"
    zig build -Doptimize=ReleaseSafe --prefix "$PREFIX_DIR"
)

BIN_PATH="${PREFIX_DIR}/bin/cbm"
[ -f "$BIN_PATH" ] || die "source build did not produce cbm"

mkdir -p "$INSTALL_DIR"
DEST="${INSTALL_DIR}/cbm"
cp "$BIN_PATH" "$DEST"
chmod 755 "$DEST"

VERSION_OUT="$("$DEST" --version 2>&1)" || die "installed binary failed to run"
echo "Installed from source: ${VERSION_OUT}"

if [ "$SKIP_CONFIG" = false ]; then
    "$DEST" install -y || echo "warning: agent configuration failed; run 'cbm install -y' manually" >&2
fi

echo "Done."
