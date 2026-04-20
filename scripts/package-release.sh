#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/dist/release"
VERSION=""
TARGETS=()

usage() {
    cat <<EOF
Usage: scripts/package-release.sh --version <version> [--output-dir <path>] [--target <zig-target> ...]

Builds release-safe cbm archives for one or more targets and writes checksums.txt
plus release-manifest.json.
If no --target values are supplied, the host target is used.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
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

host_target() {
    case "$(uname -s):$(uname -m)" in
        Darwin:arm64|Darwin:aarch64) echo "aarch64-macos" ;;
        Darwin:x86_64) echo "x86_64-macos" ;;
        Linux:arm64|Linux:aarch64) echo "aarch64-linux-musl" ;;
        Linux:x86_64) echo "x86_64-linux-musl" ;;
        *) die "unsupported host target: $(uname -s):$(uname -m)" ;;
    esac
}

archive_info() {
    case "$1" in
        aarch64-macos) echo "cbm-darwin-arm64.tar.gz|cbm|tar.gz|darwin|arm64" ;;
        x86_64-macos) echo "cbm-darwin-amd64.tar.gz|cbm|tar.gz|darwin|amd64" ;;
        aarch64-linux-musl) echo "cbm-linux-arm64.tar.gz|cbm|tar.gz|linux|arm64" ;;
        x86_64-linux-musl) echo "cbm-linux-amd64.tar.gz|cbm|tar.gz|linux|amd64" ;;
        x86_64-windows|x86_64-windows-gnu) echo "cbm-windows-amd64.zip|cbm.exe|zip|windows|amd64" ;;
        *) die "unsupported release target: $1" ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION="${1#--version=}"
            shift
            ;;
        --output-dir)
            [ "$#" -ge 2 ] || die "--output-dir requires a path"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#--output-dir=}"
            shift
            ;;
        --target)
            [ "$#" -ge 2 ] || die "--target requires a value"
            TARGETS+=("$2")
            shift 2
            ;;
        --target=*)
            TARGETS+=("${1#--target=}")
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

[ -n "$VERSION" ] || die "--version is required"
command -v zig >/dev/null 2>&1 || die "zig is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v zip >/dev/null 2>&1 || die "zip is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=("$(host_target)")
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
rm -f "${OUTPUT_DIR}/checksums.txt"
rm -f "${OUTPUT_DIR}/release-manifest.json"

WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT
METADATA_TSV="${WORK_ROOT}/release-metadata.tsv"
: > "${METADATA_TSV}"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"

for target in "${TARGETS[@]}"; do
    IFS='|' read -r archive_name binary_name archive_type os_name arch_name <<EOF
$(archive_info "$target")
EOF
    build_root="${WORK_ROOT}/${target}"
    prefix_dir="${build_root}/prefix"
    cache_dir="${build_root}/cache"
    global_cache_dir="${build_root}/global-cache"
    stage_dir="${build_root}/stage"
    mkdir -p "$stage_dir"

    (
        cd "$ROOT_DIR"
        zig build release \
            -Dversion="$VERSION" \
            -Dtarget="$target" \
            --prefix "$prefix_dir" \
            --cache-dir "$cache_dir" \
            --global-cache-dir "$global_cache_dir"
    )

    cp "${prefix_dir}/bin/${binary_name}" "${stage_dir}/${binary_name}"
    if [ "$archive_type" = "zip" ]; then
        [ -f "${ROOT_DIR}/install.ps1" ] && cp "${ROOT_DIR}/install.ps1" "${stage_dir}/install.ps1"
        (
            cd "$stage_dir"
            zip -q "${OUTPUT_DIR}/${archive_name}" ./*
        )
    else
        [ -f "${ROOT_DIR}/install.sh" ] && cp "${ROOT_DIR}/install.sh" "${stage_dir}/install.sh"
        tar -czf "${OUTPUT_DIR}/${archive_name}" -C "$stage_dir" .
    fi

    archive_path="${OUTPUT_DIR}/${archive_name}"
    checksum="$(sha256_file "${archive_path}")"
    size_bytes="$(wc -c < "${archive_path}" | tr -d ' ')"

    printf '%s  %s\n' "${checksum}" "${archive_name}" >> "${OUTPUT_DIR}/checksums.txt"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${target}" \
        "${os_name}" \
        "${arch_name}" \
        "${archive_name}" \
        "${binary_name}" \
        "${archive_type}" \
        "${checksum}" \
        "${size_bytes}" >> "${METADATA_TSV}"
    echo "packaged ${archive_name}"
done

python3 - "${VERSION}" "${SOURCE_COMMIT}" "${METADATA_TSV}" "${OUTPUT_DIR}/release-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

version, source_commit, metadata_path, manifest_path = sys.argv[1:5]
rows = []
for line in Path(metadata_path).read_text().splitlines():
    if not line.strip():
        continue
    target, os_name, arch_name, archive_name, binary_name, archive_type, checksum, size_bytes = line.split("\t")
    rows.append(
        {
            "target": target,
            "os": os_name,
            "arch": arch_name,
            "archive": archive_name,
            "binary": binary_name,
            "archive_type": archive_type,
            "sha256": checksum,
            "size_bytes": int(size_bytes),
        }
    )

rows.sort(key=lambda item: item["target"])
manifest = {
    "schema_version": 1,
    "version": version,
    "source_commit": source_commit,
    "artifacts": rows,
}
Path(manifest_path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

echo "wrote ${OUTPUT_DIR}/checksums.txt"
echo "wrote ${OUTPUT_DIR}/release-manifest.json"
