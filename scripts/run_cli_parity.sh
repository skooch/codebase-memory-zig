#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse flags before positional args
MODE="compare"
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zig-only)
      if [ "$MODE" = "update-golden" ]; then
        echo "ERROR: --zig-only and --update-golden are mutually exclusive" >&2
        exit 1
      fi
      MODE="zig-only"
      shift
      ;;
    --update-golden)
      if [ "$MODE" = "zig-only" ]; then
        echo "ERROR: --zig-only and --update-golden are mutually exclusive" >&2
        exit 1
      fi
      MODE="update-golden"
      shift
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

REPORT_DIR="${POSITIONAL_ARGS[0]:-$ROOT_DIR/.interop_reports}"
GOLDEN_DIR="$ROOT_DIR/testdata/interop/golden"
WINDOWS_FIXTURE_DIR="$ROOT_DIR/testdata/agent-comparison/windows-paths"

# C binary is only needed in compare mode
C_BIN=""
if [ "$MODE" = "compare" ]; then
  C_BIN_DEFAULT="$ROOT_DIR/../codebase-memory-mcp/build/c/codebase-memory-mcp"
  if [ ! -x "$C_BIN_DEFAULT" ]; then
    ALT_C_BIN_DEFAULT="$ROOT_DIR/../../codebase-memory-mcp/build/c/codebase-memory-mcp"
    if [ -x "$ALT_C_BIN_DEFAULT" ]; then
      C_BIN_DEFAULT="$ALT_C_BIN_DEFAULT"
    fi
  fi
  C_BIN="${CODEBASE_MEMORY_C_BIN:-$C_BIN_DEFAULT}"
fi

if [ -n "${CODEBASE_MEMORY_ZIG_BIN:-}" ]; then
  ZIG_BIN="$CODEBASE_MEMORY_ZIG_BIN"
else
  zig build >/dev/null
  ZIG_BIN="$ROOT_DIR/zig-out/bin/cbm"
fi

mkdir -p "$REPORT_DIR"

python3 - "$ZIG_BIN" "$C_BIN" "$REPORT_DIR" "$MODE" "$GOLDEN_DIR" "$WINDOWS_FIXTURE_DIR" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

zig_bin = Path(sys.argv[1])
c_bin_arg = sys.argv[2]
report_dir = Path(sys.argv[3])
mode = sys.argv[4] if len(sys.argv) > 4 else "compare"
golden_dir = Path(sys.argv[5]) if len(sys.argv) > 5 else None
fixture_dir = Path(sys.argv[6]) if len(sys.argv) > 6 else None


def contains_ci(text: str, needle: str) -> bool:
    return needle.lower() in text.lower()


def file_text(path: Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def run_cmd(
    argv: List[str],
    home: Path,
    extra_env: Optional[Dict[str, str]] = None,
    use_default_cache: bool = True,
) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["HOME"] = str(home)
    if use_default_cache:
        env["CBM_CACHE_DIR"] = str(home / ".cache" / "codebase-memory-zig")
    if extra_env:
        env.update(extra_env)
    return subprocess.run(argv, text=True, capture_output=True, env=env, check=False)


def seed_fixture(path: Path, fixture: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fixture.read_text())


def inspect_windows_layout(binary: Path, fixture_root: Path) -> Dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="cbm-cli-windows-") as tmp:
        root = Path(tmp)
        home = root / "home"
        home.mkdir(parents=True, exist_ok=True)
        appdata = home / "AppData" / "Roaming"
        localappdata = home / "AppData" / "Local"
        appdata.mkdir(parents=True, exist_ok=True)
        localappdata.mkdir(parents=True, exist_ok=True)

        vscode_path = appdata / "Code" / "User" / "mcp.json"
        zed_path = appdata / "Zed" / "settings.json"
        kilocode_path = appdata / "Code" / "User" / "globalStorage" / "kilocode.kilo-code" / "settings" / "mcp_settings.json"
        config_path = localappdata / "codebase-memory-zig" / "config.json"

        seed_fixture(vscode_path, fixture_root / "mcp.json")
        seed_fixture(zed_path, fixture_root / "settings.json")

        env = {
            "CBM_CONFIG_PLATFORM": "windows",
            "APPDATA": str(appdata),
            "LOCALAPPDATA": str(localappdata),
        }

        install = run_cmd([str(binary), "install", "-y", "--force", "--scope", "detected"], home, env, use_default_cache=False)
        config_set = run_cmd(
            [str(binary), "config", "set", "auto_index", "true"],
            home,
            env,
            use_default_cache=False,
        )

        return {
            "install": {
                "returncode": install.returncode,
                "stdout": install.stdout.splitlines(),
                "stderr": install.stderr.splitlines(),
            },
            "config_set": {
                "returncode": config_set.returncode,
                "stdout": config_set.stdout.splitlines(),
                "stderr": config_set.stderr.splitlines(),
            },
            "windows_contract": {
                "config_set_success": config_set.returncode == 0,
                "config_uses_localappdata": config_path.exists(),
                "windows_vscode_wrote_binary": str(binary) in file_text(vscode_path),
                "windows_zed_wrote_binary": str(binary) in file_text(zed_path),
                "windows_kilocode_wrote_binary": str(binary) in file_text(kilocode_path),
            },
        }


def inspect_operational_controls(binary: Path) -> Dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="cbm-cli-config-") as tmp:
        home = Path(tmp)
        home.mkdir(parents=True, exist_ok=True)
        (home / ".gemini").mkdir(parents=True, exist_ok=True)
        gemini_settings = home / ".gemini" / "settings.json"
        codex_config = home / ".codex" / "config.toml"
        claude_config = home / ".claude" / ".mcp.json"
        mcp_only_home = home / "mcp-only"
        (mcp_only_home / ".codex").mkdir(parents=True, exist_ok=True)
        (mcp_only_home / ".claude").mkdir(parents=True, exist_ok=True)
        mcp_only_codex_config = mcp_only_home / ".codex" / "config.toml"
        mcp_only_claude_config = mcp_only_home / ".claude" / ".mcp.json"
        mcp_only_codex_instructions = mcp_only_home / ".codex" / "AGENTS.md"
        mcp_only_claude_settings = mcp_only_home / ".claude" / "settings.json"

        set_idle = run_cmd([str(binary), "config", "set", "idle_store_timeout_ms", "1234"], home)
        get_idle = run_cmd([str(binary), "config", "get", "idle_store_timeout_ms"], home)
        set_update_disable = run_cmd([str(binary), "config", "set", "update_check_disable", "true"], home)
        get_update_disable = run_cmd([str(binary), "config", "get", "update_check_disable"], home)
        config_list = run_cmd([str(binary), "config", "list"], home)
        reset_idle = run_cmd([str(binary), "config", "reset", "idle_store_timeout_ms"], home)
        idle_after_reset = run_cmd([str(binary), "config", "get", "idle_store_timeout_ms"], home)
        reset_update_disable = run_cmd([str(binary), "config", "reset", "update_check_disable"], home)
        update_disable_after_reset = run_cmd([str(binary), "config", "get", "update_check_disable"], home)
        install_shipped = run_cmd([str(binary), "install", "-y", "--force"], home)
        gemini_after_shipped_exists = gemini_settings.exists()
        install_detected = run_cmd([str(binary), "install", "-y", "--force", "--scope", "detected"], home)
        install_mcp_only = run_cmd([str(binary), "install", "-y", "--force", "--mcp-only"], mcp_only_home)

        gemini_after_detected = file_text(gemini_settings)

        return {
            "operational_contract": {
                "idle_timeout_set_success": set_idle.returncode == 0,
                "idle_timeout_get_matches": get_idle.stdout.strip() == "1234",
                "update_check_disable_set_success": set_update_disable.returncode == 0,
                "update_check_disable_get_matches": get_update_disable.stdout.strip() == "true",
                "config_list_mentions_idle_timeout": contains_ci(config_list.stdout, "idle_store_timeout_ms = 1234"),
                "config_list_mentions_update_check_disable": contains_ci(config_list.stdout, "update_check_disable = true"),
                "idle_timeout_reset_restores_default": idle_after_reset.stdout.strip() == "60000",
                "update_check_disable_reset_restores_default": update_disable_after_reset.stdout.strip() == "false",
                "default_scope_mentions_shipped": contains_ci(install_shipped.stdout, "Scope: shipped"),
                "default_scope_skips_gemini": install_shipped.returncode == 0 and not gemini_after_shipped_exists,
                "default_scope_writes_codex": str(binary) in file_text(codex_config),
                "default_scope_writes_claude": str(binary) in file_text(claude_config),
                "detected_scope_mentions_detected": contains_ci(install_detected.stdout, "Scope: detected"),
                "detected_scope_writes_gemini": install_detected.returncode == 0 and str(binary) in gemini_after_detected,
                "mcp_only_mentions_mode": contains_ci(install_mcp_only.stdout, "Extras: mcp-only"),
                "mcp_only_writes_codex_config": install_mcp_only.returncode == 0 and str(binary) in file_text(mcp_only_codex_config),
                "mcp_only_writes_claude_config": install_mcp_only.returncode == 0 and str(binary) in file_text(mcp_only_claude_config),
                "mcp_only_skips_codex_instructions": not mcp_only_codex_instructions.exists(),
                "mcp_only_skips_claude_hooks": not mcp_only_claude_settings.exists(),
            },
        }


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

        windows_result = (
            inspect_windows_layout(binary, fixture_dir)
            if label == "zig" and fixture_dir is not None and fixture_dir.exists()
            else {"windows_contract": {}}
        )
        operational_result = (
            inspect_operational_controls(binary)
            if label == "zig"
            else {"operational_contract": {}}
        )

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
            "windows_contract": windows_result["windows_contract"],
            "operational_contract": operational_result["operational_contract"],
        }


GOLDEN_FILE = "cli-parity.json"


def run_update_golden(zig_result: Dict[str, Any]) -> None:
    """Write shared_contract to golden snapshot file."""
    assert golden_dir is not None, "golden_dir required for update-golden mode"
    golden_dir.mkdir(parents=True, exist_ok=True)
    golden_path = golden_dir / GOLDEN_FILE
    snapshot = {
        "shared_contract": zig_result["shared_contract"],
        "windows_contract": zig_result.get("windows_contract", {}),
        "operational_contract": zig_result.get("operational_contract", {}),
    }
    golden_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")
    print("updated: %s" % golden_path)
    print(json.dumps(snapshot, indent=2, sort_keys=True))


def run_zig_only(zig_result: Dict[str, Any]) -> None:
    """Compare Zig shared_contract against golden snapshot."""
    assert golden_dir is not None, "golden_dir required for zig-only mode"
    golden_path = golden_dir / GOLDEN_FILE
    if not golden_path.exists():
        print("FAIL: golden snapshot missing: %s" % golden_path)
        print("Run with --update-golden to create it.")
        raise SystemExit(1)

    golden = json.loads(golden_path.read_text())
    sections = {
        "shared_contract": (
            golden.get("shared_contract", {}),
            zig_result["shared_contract"],
        ),
        "windows_contract": (
            golden.get("windows_contract", {}),
            zig_result.get("windows_contract", {}),
        ),
        "operational_contract": (
            golden.get("operational_contract", {}),
            zig_result.get("operational_contract", {}),
        ),
    }
    compare_keys = []
    mismatches = []  # type: List[Dict[str, Any]]
    for section_name, (golden_contract, current_contract) in sections.items():
        section_keys = sorted(set(list(golden_contract.keys()) + list(current_contract.keys())))
        compare_keys.extend(["%s.%s" % (section_name, key) for key in section_keys])
        for key in section_keys:
            golden_val = golden_contract.get(key)
            current_val = current_contract.get(key)
            if golden_val != current_val:
                mismatches.append({
                    "key": "%s.%s" % (section_name, key),
                    "golden": golden_val,
                    "current": current_val,
                })

    # Write report
    report = {
        "mode": "zig-only",
        "zig_bin": str(zig_bin),
        "golden_path": str(golden_path),
        "keys": compare_keys,
        "mismatches": mismatches,
    }  # type: Dict[str, Any]
    json_path = report_dir / "cli_parity_report.json"
    json_path.write_text(json.dumps(report, indent=2) + "\n")

    md_lines = [
        "# CLI Parity Report (zig-only)",
        "",
        "- Zig binary: `%s`" % zig_bin,
        "- Golden: `%s`" % golden_path,
        "- Compared checks: %d" % len(compare_keys),
        "- Mismatches: %d" % len(mismatches),
        "",
        "## Summary",
    ]
    for section_name, (golden_contract, current_contract) in sections.items():
        section_keys = sorted(set(list(golden_contract.keys()) + list(current_contract.keys())))
        for key in section_keys:
            golden_val = golden_contract.get(key)
            current_val = current_contract.get(key)
            status = "match" if golden_val == current_val else "MISMATCH"
            md_lines.append(
                "- `%s.%s`: %s (current=%s, golden=%s)"
                % (section_name, key, status, current_val, golden_val)
            )
    md_path = report_dir / "cli_parity_report.md"
    md_path.write_text("\n".join(md_lines) + "\n")

    print("wrote report: %s" % json_path)
    print("wrote report: %s" % md_path)

    if mismatches:
        print("\nFAIL: %d mismatches" % len(mismatches))
        for m in mismatches:
            print("  - %s: current=%s golden=%s" % (m["key"], m["current"], m["golden"]))
        raise SystemExit(1)
    else:
        print("\nPASS: %d checks match golden snapshot" % len(compare_keys))


def run_compare(zig_result: Dict[str, Any], c_result: Dict[str, Any]) -> None:
    """Original compare mode: Zig vs C."""
    report = {
        "zig_bin": str(zig_bin),
        "c_bin": c_bin_arg,
        "zig": zig_result,
        "c": c_result,
    }  # type: Dict[str, Any]

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
        "- Zig binary: `%s`" % zig_bin,
        "- C binary: `%s`" % c_bin_arg,
        "- Compared checks: %d" % len(compare_keys),
        "- Mismatches: %d" % len(report["comparison"]["mismatches"]),
        "",
        "## Summary",
    ]
    for key in compare_keys:
        zig_ok = report["zig"]["shared_contract"][key]
        c_ok = report["c"]["shared_contract"][key]
        status = "match" if zig_ok == c_ok else "mismatch"
        lines.append("- `%s`: %s (zig=%s, c=%s)" % (key, status, zig_ok, c_ok))
    md_path.write_text("\n".join(lines) + "\n")

    print("wrote report: %s" % json_path)
    print("wrote report: %s" % md_path)
    print(json.dumps(report["comparison"], indent=2))

    if report["comparison"]["mismatches"]:
        raise SystemExit(1)


# Main dispatch
if mode in ("zig-only", "update-golden"):
    zig_result = inspect_impl("zig", zig_bin)
    if mode == "update-golden":
        run_update_golden(zig_result)
    else:
        run_zig_only(zig_result)
elif mode == "compare":
    c_bin = Path(c_bin_arg)
    zig_result = inspect_impl("zig", zig_bin)
    c_result = inspect_impl("c", c_bin)
    run_compare(zig_result, c_result)
else:
    print("ERROR: unknown mode: %s" % mode)
    raise SystemExit(1)
PY
