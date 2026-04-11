#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

C_BIN_DEFAULT="$ROOT_DIR/../codebase-memory-mcp/build/c/codebase-memory-mcp"
C_BIN="${CODEBASE_MEMORY_C_BIN:-$C_BIN_DEFAULT}"
REPORT_DIR="${1:-$ROOT_DIR/.interop_reports}"

if [ -n "${CODEBASE_MEMORY_ZIG_BIN:-}" ]; then
  ZIG_BIN="$CODEBASE_MEMORY_ZIG_BIN"
else
  zig build >/dev/null
  ZIG_BIN="$ROOT_DIR/zig-out/bin/cbm"
fi

mkdir -p "$REPORT_DIR"

python3 - "$ZIG_BIN" "$C_BIN" "$REPORT_DIR" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

zig_bin = Path(sys.argv[1])
c_bin = Path(sys.argv[2])
report_dir = Path(sys.argv[3])


def contains_ci(text: str, needle: str) -> bool:
    return needle.lower() in text.lower()


def file_text(path: Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def run_cmd(argv: list[str], home: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["CBM_CACHE_DIR"] = str(home / ".cache" / "codebase-memory-zig")
    return subprocess.run(argv, text=True, capture_output=True, env=env, check=False)


def inspect_impl(label: str, binary: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix=f"cbm-cli-{label}-") as tmp:
        home = Path(tmp)
        (home / ".codex").mkdir(parents=True, exist_ok=True)
        (home / ".claude").mkdir(parents=True, exist_ok=True)

        codex_path = home / ".codex" / "config.toml"
        claude_nested = home / ".claude" / ".mcp.json"
        claude_legacy = home / ".claude.json"

        install_cmd = [str(binary), "install", "-y"]
        update_cmd = [str(binary), "update", "-y", "--dry-run"]
        if label == "c":
            update_cmd.insert(3, "--standard")
        uninstall_dry_cmd = [str(binary), "uninstall", "-y", "--dry-run"]
        uninstall_cmd = [str(binary), "uninstall", "-y"]

        install = run_cmd(install_cmd, home)
        codex_after_install = file_text(codex_path)
        claude_nested_after_install = file_text(claude_nested)
        claude_legacy_after_install = file_text(claude_legacy)

        hashes_before_update = {
            "codex": sha256_text(codex_after_install),
            "claude_nested": sha256_text(claude_nested_after_install),
            "claude_legacy": sha256_text(claude_legacy_after_install),
        }

        update = run_cmd(update_cmd, home)
        hashes_after_update = {
            "codex": sha256_text(file_text(codex_path)),
            "claude_nested": sha256_text(file_text(claude_nested)),
            "claude_legacy": sha256_text(file_text(claude_legacy)),
        }

        uninstall_dry = run_cmd(uninstall_dry_cmd, home)
        hashes_after_uninstall_dry = {
            "codex": sha256_text(file_text(codex_path)),
            "claude_nested": sha256_text(file_text(claude_nested)),
            "claude_legacy": sha256_text(file_text(claude_legacy)),
        }

        uninstall = run_cmd(uninstall_cmd, home)
        codex_after_uninstall = file_text(codex_path)
        claude_nested_after_uninstall = file_text(claude_nested)
        claude_legacy_after_uninstall = file_text(claude_legacy)

        shared_contract = {
            "install_mentions_codex": contains_ci(install.stdout, "codex cli"),
            "install_mentions_claude": contains_ci(install.stdout, "claude code"),
            "install_mentions_codex_path": contains_ci(install.stdout, str(codex_path)),
            "install_mentions_claude_nested_path": contains_ci(install.stdout, str(claude_nested)),
            "install_mentions_claude_legacy_path": contains_ci(install.stdout, str(claude_legacy)),
            "install_wrote_codex_binary": str(binary) in codex_after_install,
            "install_wrote_claude_nested_binary": str(binary) in claude_nested_after_install,
            "install_wrote_claude_legacy_binary": str(binary) in claude_legacy_after_install,
            "update_dry_run_success": update.returncode == 0,
            "update_dry_run_mentions": contains_ci(update.stdout, "dry run") or contains_ci(update.stdout, "dry-run"),
            "update_dry_run_kept_files": hashes_before_update == hashes_after_update,
            "uninstall_dry_run_success": uninstall_dry.returncode == 0,
            "uninstall_dry_run_mentions": contains_ci(uninstall_dry.stdout, "dry run")
            or contains_ci(uninstall_dry.stdout, "dry-run"),
            "uninstall_dry_run_kept_files": hashes_after_update == hashes_after_uninstall_dry,
            "uninstall_success": uninstall.returncode == 0,
            "uninstall_removed_codex_binary": str(binary) not in codex_after_uninstall,
            "uninstall_removed_claude_nested_binary": str(binary) not in claude_nested_after_uninstall,
            "uninstall_removed_claude_legacy_binary": str(binary) not in claude_legacy_after_uninstall,
        }

        return {
            "home": str(home),
            "install": {
                "returncode": install.returncode,
                "stdout": install.stdout.splitlines(),
                "stderr": install.stderr.splitlines(),
            },
            "update_dry_run": {
                "returncode": update.returncode,
                "stdout": update.stdout.splitlines(),
                "stderr": update.stderr.splitlines(),
            },
            "uninstall_dry_run": {
                "returncode": uninstall_dry.returncode,
                "stdout": uninstall_dry.stdout.splitlines(),
                "stderr": uninstall_dry.stderr.splitlines(),
            },
            "uninstall": {
                "returncode": uninstall.returncode,
                "stdout": uninstall.stdout.splitlines(),
                "stderr": uninstall.stderr.splitlines(),
            },
            "shared_contract": shared_contract,
        }


report = {
    "zig_bin": str(zig_bin),
    "c_bin": str(c_bin),
    "zig": inspect_impl("zig", zig_bin),
    "c": inspect_impl("c", c_bin),
}

compare_keys = sorted(report["zig"]["shared_contract"].keys())
report["comparison"] = {
    "keys": compare_keys,
    "zig_passed": [key for key in compare_keys if report["zig"]["shared_contract"][key]],
    "c_passed": [key for key in compare_keys if report["c"]["shared_contract"][key]],
    "mismatches": [
        {
            "key": key,
            "zig": report["zig"]["shared_contract"][key],
            "c": report["c"]["shared_contract"][key],
        }
        for key in compare_keys
        if report["zig"]["shared_contract"][key] != report["c"]["shared_contract"][key]
    ],
}

json_path = report_dir / "cli_parity_report.json"
md_path = report_dir / "cli_parity_report.md"
json_path.write_text(json.dumps(report, indent=2) + "\n")

lines = [
    "# CLI Parity Report",
    "",
    f"- Zig binary: `{zig_bin}`",
    f"- C binary: `{c_bin}`",
    f"- Compared checks: {len(compare_keys)}",
    f"- Mismatches: {len(report['comparison']['mismatches'])}",
    "",
    "## Summary",
]
for key in compare_keys:
    zig_ok = report["zig"]["shared_contract"][key]
    c_ok = report["c"]["shared_contract"][key]
    status = "match" if zig_ok == c_ok else "mismatch"
    lines.append(f"- `{key}`: {status} (zig={zig_ok}, c={c_ok})")
md_path.write_text("\n".join(lines) + "\n")

print(f"wrote report: {json_path}")
print(f"wrote report: {md_path}")
print(json.dumps(report["comparison"], indent=2))

if report["comparison"]["mismatches"]:
    raise SystemExit(1)
PY
