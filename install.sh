#!/usr/bin/env bash
set -euo pipefail

REPO="skooch/codebase-memory-zig"
INSTALL_DIR="${HOME}/.local/bin"
SKIP_CONFIG=false
BASE_URL="${CBM_DOWNLOAD_URL:-https://github.com/${REPO}/releases/latest/download}"

usage() {
    cat <<EOF
Usage: install.sh [--dir <path>] [--dir=<path>] [--skip-config] [--base-url <url>] [--base-url=<url>]

Downloads a packaged cbm release archive, verifies checksums when available,
installs the binary, and optionally runs \`cbm install -y\`.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$output" "$url"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
        return
    fi
    die "curl or wget is required"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
        return
    fi
    die "no SHA-256 tool available"
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) die "unsupported OS: $(uname -s)" ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        arm64|aarch64) echo "arm64" ;;
        x86_64|amd64)
            if [ "$(uname -s)" = "Darwin" ] && sysctl -n hw.optional.arm64 2>/dev/null | grep -q '1'; then
                echo "arm64"
            else
                echo "amd64"
            fi
            ;;
        *) die "unsupported architecture: $arch" ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir)
            [ "$#" -ge 2 ] || die "--dir requires a path"
            INSTALL_DIR="$2"
            shift 2
            ;;
        --dir=*)
            INSTALL_DIR="${1#--dir=}"
            shift
            ;;
        --base-url)
            [ "$#" -ge 2 ] || die "--base-url requires a value"
            BASE_URL="$2"
            shift 2
            ;;
        --base-url=*)
            BASE_URL="${1#--base-url=}"
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

need_cmd tar

OS="$(detect_os)"
ARCH="$(detect_arch)"
ARCHIVE="cbm-${OS}-${ARCH}.tar.gz"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading ${ARCHIVE}..."
download_file "${BASE_URL}/${ARCHIVE}" "${TMP_DIR}/${ARCHIVE}"

if download_file "${BASE_URL}/checksums.txt" "${TMP_DIR}/checksums.txt" 2>/dev/null; then
    :
fi

if [ -f "${TMP_DIR}/checksums.txt" ]; then
    EXPECTED="$(awk -v name="$ARCHIVE" '$2 == name { print $1 }' "${TMP_DIR}/checksums.txt")"
    if [ -n "$EXPECTED" ]; then
        ACTUAL="$(sha256_file "${TMP_DIR}/${ARCHIVE}")"
        [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for ${ARCHIVE}"
        echo "Checksum verified."
    fi
fi

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "$TMP_DIR"

BIN_PATH="${TMP_DIR}/cbm"
[ -f "$BIN_PATH" ] || die "archive did not contain cbm"

mkdir -p "$INSTALL_DIR"
DEST="${INSTALL_DIR}/cbm"
cp "$BIN_PATH" "$DEST"
chmod 755 "$DEST"

VERSION_OUT="$("$DEST" --version 2>&1)" || die "installed binary failed to run"
echo "Installed: ${VERSION_OUT}"

if [ "$SKIP_CONFIG" = true ]; then
    echo "Skipping agent configuration (--skip-config)"
else
    echo "Configuring coding agents..."
    "$DEST" install -y || echo "warning: agent configuration failed; run 'cbm install -y' manually" >&2
fi

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo "NOTE: ${INSTALL_DIR} is not currently on PATH"
fi

echo "Done."
