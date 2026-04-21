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

MANIFEST_PATH="${POSITIONAL_ARGS[0]:-$ROOT_DIR/testdata/interop/manifest.json}"
REPORT_DIR="${POSITIONAL_ARGS[1]:-$ROOT_DIR/.interop_reports}"
GOLDEN_DIR="$ROOT_DIR/testdata/interop/golden"

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
  ZIG_CACHE_DIR="${CODEBASE_MEMORY_ZIG_CACHE_DIR:-$ROOT_DIR/.zig-cache-interop}"
  ZIG_GLOBAL_CACHE_DIR="${CODEBASE_MEMORY_ZIG_GLOBAL_CACHE_DIR:-$ROOT_DIR/.zig-global-cache-interop}"
  ZIG_PREFIX_DIR="${CODEBASE_MEMORY_ZIG_PREFIX:-$ROOT_DIR/.zig-prefix-interop}"
  zig build --cache-dir "$ZIG_CACHE_DIR" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" --prefix "$ZIG_PREFIX_DIR" >/dev/null
  ZIG_BIN="$ZIG_PREFIX_DIR/bin/cbm"
fi

if [ ! -d "$REPORT_DIR" ]; then
  mkdir -p "$REPORT_DIR"
fi

python3 - "$MANIFEST_PATH" "$ROOT_DIR" "$C_BIN" "$ZIG_BIN" "$REPORT_DIR" "$MODE" "$GOLDEN_DIR" <<'PY'
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

SHARED_TOOL_NAMES = [
    "delete_project",
    "detect_changes",
    "get_architecture",
    "get_code_snippet",
    "get_graph_schema",
    "index_repository",
    "index_status",
    "list_projects",
    "manage_adr",
    "query_graph",
    "search_code",
    "search_graph",
    "trace_call_path",
]

SHARED_PROGRESS_PHASES = (
    "Discovering files",
    "Starting full index",
    "Starting incremental index",
    "[1/9] Building file structure",
    "[2/9] Extracting definitions",
    "[3/9] Building registry",
    "[4/9] Resolving calls & edges",
    "[5/9] Detecting tests",
    # [6/9] intentionally does not exist
    "[7/9] Analyzing git history",
    "[8/9] Linking config files",
    "[9/9] Writing database",
    "Done",
)


def to_unix_path(path: str) -> str:
    return str(Path(path).as_posix())


def normalize_path_for_manifest(path: str) -> str:
    return to_unix_path(path)


def normalize_project_name_for_c(project_path: str) -> str:
    unix_path = normalize_path_for_manifest(project_path)
    normalized = unix_path.replace("/", "-")
    return normalized.lstrip("-")


def clear_directory(path: Path) -> None:
    if not path.exists():
        return
    for child in path.iterdir():
        if child.name == ".git":
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def copy_directory_contents(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        if child.name == ".git":
            continue
        target = destination / child.name
        if child.is_dir():
            shutil.copytree(child, target)
        else:
            shutil.copy2(child, target)


def run_checked(args: list[str], cwd: Path) -> None:
    subprocess.run(args, cwd=str(cwd), check=True, capture_output=True, text=True)


def prepare_fixture_project(root: Path, fixture: dict[str, Any]) -> Tuple[Path, Optional[tempfile.TemporaryDirectory[str]]]:
    source_root = root / fixture.get("path", "")
    runtime_setup = fixture.get("runtime_setup", {})
    if not runtime_setup:
        return source_root, None

    fixture_id = fixture.get("id", fixture.get("project", "fixture"))
    tempdir: tempfile.TemporaryDirectory[str] = tempfile.TemporaryDirectory(prefix=f"cbm-fixture-{fixture_id}-")
    project_root = Path(tempdir.name) / str(fixture.get("project", "project"))
    project_root.mkdir(parents=True, exist_ok=True)

    kind = runtime_setup.get("kind", "")
    if kind != "git_snapshots":
        tempdir.cleanup()
        raise ValueError(f"unsupported runtime_setup.kind for {fixture_id}: {kind}")

    snapshots = runtime_setup.get("snapshots", [])
    if not isinstance(snapshots, list) or not snapshots:
        tempdir.cleanup()
        raise ValueError(f"git_snapshots runtime setup requires non-empty snapshots for {fixture_id}")

    commit_messages = runtime_setup.get("commit_messages", [])
    if commit_messages and len(commit_messages) != len(snapshots):
        tempdir.cleanup()
        raise ValueError(f"commit_messages length mismatch for {fixture_id}")

    run_checked(["git", "init"], project_root)
    run_checked(["git", "config", "user.name", "CBM Fixture"], project_root)
    run_checked(["git", "config", "user.email", "fixture@example.invalid"], project_root)

    for index, rel_snapshot in enumerate(snapshots):
        snapshot_root = source_root / str(rel_snapshot)
        if not snapshot_root.is_dir():
            tempdir.cleanup()
            raise ValueError(f"missing snapshot for {fixture_id}: {snapshot_root}")
        clear_directory(project_root)
        copy_directory_contents(snapshot_root, project_root)
        run_checked(["git", "add", "-A"], project_root)
        message = (
            str(commit_messages[index])
            if index < len(commit_messages)
            else f"fixture snapshot {index + 1}"
        )
        run_checked(["git", "commit", "--no-gpg-sign", "-m", message], project_root)

    return project_root, tempdir


def rewrite_qualified_name_project(qualified_name: str, project: str) -> str:
    if not qualified_name or ":" not in qualified_name:
        return qualified_name
    _, remainder = qualified_name.split(":", 1)
    return f"{project}:{remainder}"


def snippet_lookup_name(qualified_name: str) -> str:
    if not qualified_name:
        return qualified_name
    leaf = qualified_name.rsplit(":", 1)[-1]
    if "." in leaf:
        leaf = leaf.rsplit(".", 1)[-1]
    return leaf


def parse_rpc_envelope(raw: str) -> dict[str, Any]:
    line = raw.strip()
    if not line:
        raise ValueError("empty response line")
    payload = json.loads(line)
    if "result" not in payload and "error" not in payload:
        raise ValueError(f"missing result/error: {payload}")
    return payload


def extract_tool_payload(raw: str, allow_content_wrapper: bool = True) -> Tuple[Union[Dict[str, Any], List[Any], str], Optional[str]]:
    envelope = parse_rpc_envelope(raw)
    if "error" in envelope:
        return {"__error__": envelope.get("error")}, "error"

    result = envelope.get("result")
    status = None
    if isinstance(result, dict) and "content" in result and allow_content_wrapper:
        content = result.get("content")
        if isinstance(content, list) and content:
            text = content[0].get("text", "")
            try:
                result = json.loads(text)
            except Exception:
                result = text
            status = "ok"
        elif isinstance(content, list):
            result = []
            status = "ok"
    else:
        status = "ok"
    return result, status


def canonical_symbol_identity(value: Any) -> str:
    text = str(value or "")
    for separator in (":", "."):
        if separator in text:
            text = text.rsplit(separator, 1)[-1]
    return text


def canonical_search_nodes(payload: Any) -> list[dict[str, str]]:
    if not isinstance(payload, dict):
        return []
    nodes = payload.get("nodes", payload.get("results", []))
    if not isinstance(nodes, list):
        return []
    normalized = []
    for row in nodes:
        if not isinstance(row, dict):
            continue
        normalized.append(
            {
                "label": str(row.get("label", "")),
                "name": str(row.get("name", "")),
                "qualified_name": str(row.get("qualified_name", "")),
                "file_path": normalize_path_for_manifest(str(row.get("file_path", ""))),
            }
        )
    normalized.sort(key=lambda item: (item["name"], item["file_path"], item["qualified_name"]))
    return normalized


def canonical_query(payload: Any, preserve_order: bool = False) -> tuple[tuple[str, ...], list[tuple[str, ...]]]:
    if not isinstance(payload, dict):
        return tuple(), []
    columns = []
    for col in payload.get("columns", []):
        text = str(col)
        lowered = text.lower()
        if lowered == "count" or lowered.startswith("count("):
            columns.append("count")
        else:
            columns.append(text)
    rows = []
    for row in payload.get("rows", []):
        if not isinstance(row, list):
            continue
        rows.append(tuple(str(cell) for cell in row))
    if not preserve_order:
        rows.sort()
    return tuple(columns), rows


def canonical_trace(payload: Any) -> list[tuple[str, str, str]]:
    if payload is None:
        return []
    if isinstance(payload, dict) and "__error__" in payload:
        return []

    # Zig returns explicit edges.
    edges = []
    if isinstance(payload, dict) and isinstance(payload.get("edges"), list):
        for edge in payload.get("edges"):
            if not isinstance(edge, dict):
                continue
            source = edge.get("source_qualified_name", edge.get("source_name", edge.get("source", "")))
            target = edge.get("target_qualified_name", edge.get("target_name", edge.get("target", "")))
            edges.append(
                (
                    canonical_symbol_identity(source),
                    canonical_symbol_identity(target),
                    str(edge.get("type", "")),
                )
            )
        edges.sort()
        return edges

    # C returns a shape like {function, direction, callees:[], callers:[]} or empty.
    if not isinstance(payload, dict):
        return []
    function_name = str(payload.get("function_name", payload.get("function", "")))
    for callee in payload.get("callees", []) or []:
        if isinstance(callee, dict):
            target = callee.get("qualified_name", callee.get("name", ""))
        else:
            target = callee
        edges.append((canonical_symbol_identity(function_name), canonical_symbol_identity(target), "CALLS"))
    for caller in payload.get("callers", []) or []:
        if isinstance(caller, dict):
            source = caller.get("qualified_name", caller.get("name", ""))
        else:
            source = caller
        edges.append((canonical_symbol_identity(source), canonical_symbol_identity(function_name), "CALLS"))
    edges.sort()
    return edges


def _normalize_trace_direction(direction: str) -> str:
    lowered = direction.lower()
    if lowered in ("outbound", "out"):
        return "out"
    if lowered in ("inbound", "in"):
        return "in"
    return lowered


def canonical_trace_contract(payload: Any) -> dict[str, Any]:
    error = canonical_error(payload)
    if error is not None:
        return {"error": error}
    if not isinstance(payload, dict):
        return {}

    def normalize_entries(values: Any) -> list[dict[str, Any]]:
        if not isinstance(values, list):
            return []
        normalized: list[dict[str, Any]] = []
        for value in values:
            if isinstance(value, dict):
                symbol = canonical_symbol_identity(
                    value.get("qualified_name", value.get("name", ""))
                )
                normalized.append(
                    {
                        "symbol": symbol,
                        "hop": int(value.get("hop", 0) or 0),
                        "risk": str(value.get("risk", "")),
                        "is_test": bool(value.get("is_test", False)),
                    }
                )
            else:
                normalized.append(
                    {
                        "symbol": canonical_symbol_identity(value),
                        "hop": 0,
                        "risk": "",
                        "is_test": False,
                    }
                )
        normalized.sort(key=lambda item: (item["hop"], item["symbol"], item["risk"], item["is_test"]))
        return normalized

    return {
        "function": canonical_symbol_identity(payload.get("function_name", payload.get("function", ""))),
        "direction": _normalize_trace_direction(str(payload.get("direction", ""))),
        "mode": str(payload.get("mode", "")) or "calls",
        "edges": canonical_trace(payload),
        "callees": normalize_entries(payload.get("callees", [])),
        "callers": normalize_entries(payload.get("callers", [])),
    }


def canonical_list_projects(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        projects = payload.get("projects", [])
    elif isinstance(payload, list):
        projects = payload
    else:
        projects = []
    normalized: list[dict[str, Any]] = []
    for project in projects:
        if not isinstance(project, dict):
            continue
        normalized.append(
            {
                "name": str(project.get("name", "")),
                "root_path": normalize_path_for_manifest(str(project.get("root_path", ""))),
                "nodes": str(project.get("nodes", "")),
                "edges": str(project.get("edges", "")),
            }
        )
    normalized.sort(key=lambda item: item["name"])
    return normalized


def canonical_tools_list(payload: Any) -> list[str]:
    if not isinstance(payload, dict):
        return []
    tools = payload.get("tools", [])
    if not isinstance(tools, list):
        return []
    normalized: list[str] = []
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        name = str(tool.get("name", ""))
        if name == "trace_path":
            name = "trace_call_path"
        if name:
            normalized.append(name)
    normalized.sort()
    return normalized


def canonical_initialize_result(payload: Any) -> dict[str, str]:
    if not isinstance(payload, dict):
        return {"protocolVersion": ""}
    return {
        "protocolVersion": str(payload.get("protocolVersion", "")),
    }


def canonical_tool_schema_contract(payload: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(payload, dict):
        return {}
    tools = payload.get("tools", [])
    if not isinstance(tools, list):
        return {}

    normalized: dict[str, dict[str, Any]] = {}
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        name = str(tool.get("name", ""))
        if name == "trace_path":
            name = "trace_call_path"
        if not name:
            continue
        schema = tool.get("inputSchema", {})
        properties = schema.get("properties", {}) if isinstance(schema, dict) else {}
        if not isinstance(properties, dict):
            properties = {}
        entry: dict[str, Any] = {
            "property_keys": sorted(str(key) for key in properties.keys()),
            "required": sorted(str(item) for item in schema.get("required", [])) if isinstance(schema, dict) and isinstance(schema.get("required", []), list) else [],
        }
        mode = properties.get("mode")
        if isinstance(mode, dict) and isinstance(mode.get("enum"), list):
            entry["mode_enum"] = [str(item) for item in mode.get("enum", [])]
        normalized[name] = entry
    return normalized


def select_tool_schema_fields(
    available: dict[str, Any],
    requested: Any,
) -> dict[str, Any]:
    if not isinstance(available, dict):
        return {"missing": True}
    if not isinstance(requested, dict) or not requested:
        return dict(available)

    selected: dict[str, Any] = {}
    for key in requested.keys():
        if key in available:
            selected[str(key)] = available[key]
    return selected


def canonical_architecture(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {
            "project": "",
            "total_nodes": 0,
            "total_edges": 0,
            "node_labels": [],
            "edge_types": [],
        }

    def collect_named(entries: Any, key: str) -> list[str]:
        if not isinstance(entries, list):
            return []
        out: list[str] = []
        for entry in entries:
            if isinstance(entry, dict) and entry.get(key):
                out.append(str(entry[key]))
        return sorted(set(out))

    def collect_counted(entries: Any, key: str) -> list[dict[str, Any]]:
        if not isinstance(entries, list):
            return []
        out: list[dict[str, Any]] = []
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get(key):
                continue
            out.append(
                {
                    key: str(entry[key]),
                    "count": int(entry.get("count", 0) or 0),
                }
            )
        out.sort(key=lambda item: (item[key], item["count"]))
        return out

    def collect_symbol_rows(entries: Any) -> list[dict[str, Any]]:
        if not isinstance(entries, list):
            return []
        out: list[dict[str, Any]] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            out.append(
                {
                    "name": str(entry.get("name", "")),
                    "symbol": canonical_symbol_identity(entry.get("qualified_name", entry.get("name", ""))),
                    "file_path": normalize_path_for_manifest(str(entry.get("file_path", ""))),
                    "label": str(entry.get("label", "")),
                    "in_degree": int(entry.get("in_degree", 0) or 0),
                    "out_degree": int(entry.get("out_degree", 0) or 0),
                }
            )
        return out

    def collect_routes(entries: Any) -> list[dict[str, str]]:
        if not isinstance(entries, list):
            return []
        out: list[dict[str, str]] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            out.append(
                {
                    "name": str(entry.get("name", "")),
                    "file_path": normalize_path_for_manifest(str(entry.get("file_path", ""))),
                    "target": str(entry.get("target", "")),
                    "type": str(entry.get("type", "")),
                }
            )
        out.sort(key=lambda item: (item["name"], item["file_path"], item["target"], item["type"]))
        return out

    def collect_messages(entries: Any) -> list[dict[str, Any]]:
        if not isinstance(entries, list):
            return []
        out: list[dict[str, Any]] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            emitters = sorted(str(item) for item in entry.get("emitters", []) if isinstance(item, str))
            subscribers = sorted(str(item) for item in entry.get("subscribers", []) if isinstance(item, str))
            out.append(
                {
                    "name": str(entry.get("name", "")),
                    "file_path": normalize_path_for_manifest(str(entry.get("file_path", ""))),
                    "emitters": emitters,
                    "subscribers": subscribers,
                }
            )
        out.sort(key=lambda item: (item["name"], item["file_path"]))
        return out

    normalized = {
        "project": str(payload.get("project", "")),
        "total_nodes": int(payload.get("total_nodes", 0) or 0),
        "total_edges": int(payload.get("total_edges", 0) or 0),
        "node_labels": collect_named(payload.get("node_labels"), "label"),
        "edge_types": collect_named(payload.get("edge_types"), "type"),
    }
    if "languages" in payload:
        normalized["languages"] = collect_counted(payload.get("languages"), "language")
    if "packages" in payload:
        normalized["packages"] = collect_counted(payload.get("packages"), "name")
    if "hotspots" in payload:
        normalized["hotspots"] = collect_symbol_rows(payload.get("hotspots"))
    if "entry_points" in payload:
        normalized["entry_points"] = collect_symbol_rows(payload.get("entry_points"))
    if "routes" in payload:
        normalized["routes"] = collect_routes(payload.get("routes"))
    if "messages" in payload:
        normalized["messages"] = collect_messages(payload.get("messages"))
    return normalized


def canonical_search_code(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"total_results": 0, "results": []}
    results = payload.get("results", [])
    normalized: list[dict[str, Any]] = []
    if isinstance(results, list):
        for row in results:
            if not isinstance(row, dict):
                continue
            normalized.append(
                {
                    "file_path": normalize_path_for_manifest(str(row.get("file_path", row.get("file", "")))),
                    "name": str(row.get("name", row.get("node", ""))),
                    "label": str(row.get("label", "")),
                    "start_line": int(row.get("start_line", 0) or 0),
                    "end_line": int(row.get("end_line", 0) or 0),
                    "snippet": str(row.get("source", row.get("snippet", ""))).rstrip("\n"),
                    "match_lines": [int(value) for value in row.get("match_lines", []) if isinstance(value, int)],
                }
            )
    if not normalized:
        files = payload.get("files", [])
        if isinstance(files, list):
            normalized = [
                {
                    "file_path": normalize_path_for_manifest(str(path)),
                    "name": "",
                    "label": "",
                    "start_line": 0,
                    "end_line": 0,
                    "snippet": "",
                    "match_lines": [],
                }
                for path in files
            ]
    return {
        "total_results": int(payload.get("total_results", payload.get("total", len(normalized))) or 0),
        "results": normalized,
    }


def canonical_detect_changes(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"changed_files": [], "changed_count": 0, "impacted_symbols": []}

    changed_files = payload.get("changed_files", [])
    impacted_symbols = payload.get("impacted_symbols", [])

    normalized_impacted = []
    if isinstance(impacted_symbols, list):
        for item in impacted_symbols:
            if not isinstance(item, dict):
                continue
            normalized_impacted.append(
                {
                    "name": str(item.get("name", "")),
                    "label": str(item.get("label", "")),
                    "file_path": normalize_path_for_manifest(str(item.get("file_path", item.get("file", "")))),
                }
            )
    normalized_impacted.sort(key=lambda item: (item["name"], item["file_path"], item["label"]))

    normalized_files = []
    if isinstance(changed_files, list):
        normalized_files = sorted(normalize_path_for_manifest(str(path)) for path in changed_files)

    return {
        "changed_files": normalized_files,
        "changed_count": int(payload.get("changed_count", len(normalized_files)) or 0),
        "impacted_symbols": normalized_impacted,
    }


def canonical_manage_adr(payload: Any) -> dict[str, Any]:
    def decode_text(text: str) -> str:
        if "\\" not in text:
            return text
        try:
            return bytes(text, "utf-8").decode("unicode_escape")
        except Exception:
            return text

    def expand_sections(values: list[str]) -> list[str]:
        expanded: list[str] = []
        for value in values:
            decoded = decode_text(value)
            if "\n" not in decoded:
                expanded.append(decoded)
                continue
            for line in decoded.splitlines():
                line = line.rstrip("\r")
                if line.startswith("#"):
                    expanded.append(line)
        return expanded

    if not isinstance(payload, dict):
        return {"status": "", "content": "", "sections": []}
    sections = payload.get("sections", [])
    normalized_sections = []
    if isinstance(sections, list):
        normalized_sections = expand_sections([str(section) for section in sections])
    return {
        "status": str(payload.get("status", "")),
        "content": decode_text(str(payload.get("content", ""))),
        "sections": normalized_sections,
    }


def canonical_contract_tool_result(payload: Any) -> dict[str, Any]:
    error = canonical_error(payload)
    if error is not None:
        return {"error": error}
    if not isinstance(payload, dict):
        return {"value": payload}

    if "nodes" in payload or "edges" in payload or payload.get("status") == "indexed":
        return {
            "status": "indexed",
            "has_nodes": "nodes" in payload,
            "has_edges": "edges" in payload,
        }

    normalized: dict[str, Any] = {}
    for key in ("status", "project", "mode", "traces_received", "note"):
        if key in payload:
            normalized[key] = payload.get(key)
    return normalized


def canonical_graph_schema(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"project": "", "status": "", "nodes": 0, "edges": 0, "node_labels": [], "edge_types": [], "languages": []}
    node_labels = payload.get("node_labels", [])
    edge_types = payload.get("edge_types", [])
    languages = payload.get("languages", [])
    if not isinstance(node_labels, list):
        node_labels = []
    if not isinstance(edge_types, list):
        edge_types = []
    if not isinstance(languages, list):
        languages = []
    def collect_strings(entries: Any, key: str) -> list[str]:
        if not isinstance(entries, list):
            return []
        out: list[str] = []
        for entry in entries:
            if isinstance(entry, dict) and entry.get(key):
                out.append(str(entry[key]))
            elif isinstance(entry, str):
                out.append(entry)
        return sorted(set(out))

    return {
        "project": str(payload.get("project", "")),
        "status": str(payload.get("status", "")),
        "nodes": int(payload.get("nodes", 0) or 0),
        "edges": int(payload.get("edges", 0) or 0),
        "node_labels": collect_strings(node_labels, "label"),
        "edge_types": collect_strings(edge_types, "type"),
        "languages": sorted(
            str(entry.get("language", ""))
            for entry in languages
            if isinstance(entry, dict) and entry.get("language")
        ),
    }


def canonical_code_snippet(payload: Any) -> dict[str, Any]:
    if isinstance(payload, str) and "symbol not found" in payload.lower():
        return {"status": "not_found", "qualified_name": "", "source": "", "file_path": ""}
    if isinstance(payload, dict) and "__error__" in payload:
        error_payload = payload.get("__error__", {})
        if isinstance(error_payload, dict) and "symbol not found" in str(error_payload.get("message", "")).lower():
            return {"status": "not_found", "qualified_name": "", "source": "", "file_path": ""}
        return {"status": "error", "qualified_name": "", "source": "", "file_path": ""}
    if not isinstance(payload, dict):
        return {"status": "", "qualified_name": "", "source": "", "file_path": ""}
    if payload.get("status") == "ambiguous":
        suggestions = payload.get("suggestions", [])
        normalized_suggestions = []
        if isinstance(suggestions, list):
            for suggestion in suggestions:
                if not isinstance(suggestion, dict):
                    continue
                normalized_suggestions.append(
                    {
                        "symbol": canonical_symbol_identity(suggestion.get("qualified_name", suggestion.get("name", ""))),
                        "name": str(suggestion.get("name", "")),
                        "label": str(suggestion.get("label", "")),
                        "file_path": Path(normalize_path_for_manifest(str(suggestion.get("file_path", "")))).name,
                    }
                )
        normalized_suggestions.sort(key=lambda item: (item["symbol"], item["file_path"]))
        return {
            "status": "ambiguous",
            "message": str(payload.get("message", "")),
            "suggestions": normalized_suggestions,
        }
    fp = str(payload.get("file_path", ""))
    qn = str(payload.get("qualified_name", ""))
    # Make file_path relative: extract project name from qualified_name
    # (first :-component) and strip any absolute prefix through the project dir.
    project = qn.split(":")[0] if ":" in qn else ""
    if project:
        marker = "/%s/" % project
        idx = fp.find(marker)
        if idx >= 0:
            fp = fp[idx + len(marker):]
        elif fp.startswith(project + "/"):
            fp = fp[len(project) + 1:]
    if fp == ".":
        fp = ""
    return {
        "status": "ok",
        "name": str(payload.get("name", "")),
        "label": str(payload.get("label", "")),
        "qualified_name": qn,
        "source": str(payload.get("source", "")),
        "file_path": normalize_path_for_manifest(fp),
        "start_line": int(payload.get("start_line", 0) or 0),
        "end_line": int(payload.get("end_line", 0) or 0),
        "match_method": str(payload.get("match_method", "")),
        "callers": int(payload.get("callers", 0) or 0),
        "callees": int(payload.get("callees", 0) or 0),
        "caller_names": sorted(str(value) for value in payload.get("caller_names", []) if isinstance(value, str)),
        "callee_names": sorted(str(value) for value in payload.get("callee_names", []) if isinstance(value, str)),
        "signature": str(payload.get("signature", "")),
        "is_exported": bool(payload.get("is_exported", False)),
    }


def comparable_code_snippet(payload: Any) -> dict[str, str]:
    snippet = canonical_code_snippet(payload)
    if snippet.get("status") == "ambiguous":
        return {
            "status": "ambiguous",
            "suggestions": snippet.get("suggestions", []),
            "message": str(snippet.get("message", "")),
        }
    file_path = str(snippet.get("file_path", ""))
    if file_path:
        file_path = Path(file_path).name
    return {
        "status": str(snippet.get("status", "")),
        "name": str(snippet.get("name", "")),
        "label": str(snippet.get("label", "")),
        "symbol": snippet_lookup_name(str(snippet.get("qualified_name", ""))),
        "source": str(snippet.get("source", "")).rstrip("\n"),
        "file_path": file_path,
        "start_line": int(snippet.get("start_line", 0) or 0),
        "end_line": int(snippet.get("end_line", 0) or 0),
        "callers": int(snippet.get("callers", 0) or 0),
        "callees": int(snippet.get("callees", 0) or 0),
        "caller_names": snippet.get("caller_names", []),
        "callee_names": snippet.get("callee_names", []),
    }


def canonical_index_status(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"status": "unknown"}
    return {
        "status": str(payload.get("status", "unknown")),
    }


def canonical_delete_project(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"deleted": False}
    deleted = (
        payload.get("status") == "deleted"
        or payload.get("success", False)
    )
    return {
        "status": str(payload.get("status", "")),
        "deleted": bool(deleted),
    }


def send_rpc_request(process: subprocess.Popen[str], request: dict[str, Any]) -> tuple[dict[str, Any], str]:
    assert process.stdin is not None
    assert process.stdout is not None

    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()

    buffer = ""
    while True:
        ready, _, _ = select.select([process.stdout], [], [], 15.0)
        if not ready:
            raise TimeoutError(f"timed out waiting for response to request id {request.get('id')}: {json.dumps(request)}")
        line = process.stdout.readline()
        if line == "":
            raise ValueError(f"missing response for request id {request.get('id')}")
        if not line.strip():
            continue
        buffer += line
        stripped = buffer.strip()
        if not stripped:
            continue
        try:
            return json.loads(stripped), stripped
        except json.JSONDecodeError:
            continue


def resolve_qualified_name(
    process: subprocess.Popen[str],
    project: str,
    name_hint: str,
    request_id: int,
) -> Tuple[Optional[str], Dict[str, Any], str]:
    request = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {
            "name": "search_graph",
            "arguments": {
                "project": project,
                "name_pattern": name_hint,
                "limit": 25,
            },
        },
    }
    response, raw = send_rpc_request(process, request)
    payload, _ = extract_tool_payload(json.dumps(response))
    matches = [node for node in canonical_search_nodes(payload) if node["name"] == name_hint]
    preferred_labels = {"Function", "Method", "Class", "Interface", "Trait", "Struct"}
    preferred_matches = [node for node in matches if node["label"] in preferred_labels]
    if len(preferred_matches) == 1:
        return preferred_matches[0]["qualified_name"], response, raw
    if len(matches) == 1:
        return matches[0]["qualified_name"], response, raw
    if len(matches) > 1:
        return None, response, raw
    return None, response, raw


def call_mcp_sequence(
    bin_path: str,
    project_path: str,
    scenario: list[dict[str, Any]],
    impl: str,
) -> dict[str, Any]:
    env = os.environ.copy()
    temp_home = tempfile.TemporaryDirectory(prefix=f"cbm-interop-{impl}-")
    env["HOME"] = temp_home.name
    env["CBM_CACHE_DIR"] = str(Path(temp_home.name) / ".cache" / "codebase-memory-zig")

    process = subprocess.Popen(
        [bin_path],
        cwd=str(Path(project_path).parent),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=env,
    )

    tool_results: dict[str, Any] = {
        "tool": {},
        "stdout": [],
        "stderr": [],
        "resolution_failures": [],
    }
    internal_request_id = 100000

    try:
        for spec in scenario:
            request = json.loads(json.dumps(spec["request"]))
            if spec.get("compare_key") == "trace_call_path" and impl == "zig":
                args = request["params"]["arguments"]
                if "start_node_qn" not in args and args.get("start_node_name_hint"):
                    resolved_qn, resolution_response, resolution_raw = resolve_qualified_name(
                        process,
                        str(args["project"]),
                        str(args["start_node_name_hint"]),
                        internal_request_id,
                    )
                    internal_request_id += 1
                    tool_results["stdout"].append(resolution_raw)
                    if resolved_qn is None:
                        tool_results["resolution_failures"].append(
                            {
                                "project": args["project"],
                                "name_hint": args["start_node_name_hint"],
                                "response": resolution_response,
                            }
                        )
                        args["start_node_qn"] = args["start_node_name_hint"]
                    else:
                        args["start_node_qn"] = resolved_qn
                    args.pop("start_node_name_hint", None)

            response, raw = send_rpc_request(process, request)
            tool_results["stdout"].append(raw)

            if spec.get("compare_key") is None:
                tool_results["initialize"] = response
                continue

            payload, status = extract_tool_payload(json.dumps(response))
            tool_results["tool"].setdefault(spec["compare_key"], []).append(
                {
                    "status": status,
                    "payload": payload,
                    "raw": response,
                    "id": response.get("id"),
                    "assertion": spec.get("assertion"),
                    "request": request,
                }
            )
    finally:
        try:
            if process.stdin is not None and not process.stdin.closed:
                process.stdin.close()
            try:
                process.terminate()
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            if process.stdout is not None:
                remainder = process.stdout.read()
                if remainder:
                    tool_results["stdout"].extend([line for line in remainder.splitlines() if line.strip()])
            if process.stderr is not None:
                stderr = process.stderr.read()
                if stderr:
                    tool_results["stderr"] = stderr.splitlines()
            if process.returncode is None:
                process.kill()
        finally:
            temp_home.cleanup()

    return tool_results


def canonical_progress_lines(stderr_lines: list[str]) -> list[str]:
    normalized: list[str] = []
    for raw in stderr_lines:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("Discovering files") or line.startswith("Starting "):
            normalized.append(line)
            continue
        if (line.startswith("[1/9]") or line.startswith("[2/9]") or line.startswith("[3/9]") or line.startswith("[4/9]")
                or line.startswith("[5/9]")
                # [6/9] intentionally absent
                or line.startswith("[7/9]") or line.startswith("[8/9]")
                or line.startswith("[9/9]")):
            normalized.append(line)
            continue
        if line.startswith("Done:") or line == "Done.":
            normalized.append("Done")
    return normalized


def expand_contract_value(value: Any, impl: str, tool_ctx: dict[str, str]) -> Any:
    if isinstance(value, str):
        if value == "$PROJECT":
            return tool_ctx["project"] if impl == "zig" else tool_ctx["c_project"]
        if value == "$PROJECT_PATH":
            return tool_ctx["project_path"]
        return value
    if isinstance(value, list):
        return [expand_contract_value(item, impl, tool_ctx) for item in value]
    if isinstance(value, dict):
        return {
            str(key): expand_contract_value(item, impl, tool_ctx)
            for key, item in value.items()
        }
    return value


def run_cli_progress(bin_path: str, project_path: str, impl: str) -> dict[str, Any]:
    env = os.environ.copy()
    temp_home = tempfile.TemporaryDirectory(prefix=f"cbm-progress-{impl}-")
    env["HOME"] = temp_home.name
    env["CBM_CACHE_DIR"] = str(Path(temp_home.name) / ".cache" / "codebase-memory-zig")
    args = json.dumps({"repo_path": project_path})
    proc = subprocess.run(
        [bin_path, "cli", "--progress", "index_repository", args],
        cwd=str(Path(project_path).parent),
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    temp_home.cleanup()
    return {
        "returncode": proc.returncode,
        "stdout": [line for line in proc.stdout.splitlines() if line.strip()],
        "stderr": [line for line in proc.stderr.splitlines() if line.strip()],
        "progress": canonical_progress_lines(proc.stderr.splitlines()),
    }


def parse_cli_tool_payload(stdout_lines: list[str]) -> Any:
    if not stdout_lines:
        return {}
    raw = stdout_lines[-1].strip()
    if not raw:
        return {}
    try:
        payload = json.loads(raw)
    except Exception:
        return {"__raw__": raw}

    if isinstance(payload, dict) and "jsonrpc" in payload and ("result" in payload or "error" in payload):
        result, _ = extract_tool_payload(raw)
        return result

    if isinstance(payload, dict) and "content" in payload:
        content = payload.get("content")
        if isinstance(content, list) and content:
            text = str(content[0].get("text", ""))
            try:
                return json.loads(text)
            except Exception:
                return {"text": text}

    return payload


def run_cli_tool(bin_path: str, project_path: str, impl: str, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    env = os.environ.copy()
    temp_home = tempfile.TemporaryDirectory(prefix=f"cbm-cli-{impl}-")
    env["HOME"] = temp_home.name
    env["CBM_CACHE_DIR"] = str(Path(temp_home.name) / ".cache" / "codebase-memory-zig")
    proc = subprocess.run(
        [bin_path, "cli", name, json.dumps(arguments)],
        cwd=str(Path(project_path).parent),
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    stdout_lines = [line for line in proc.stdout.splitlines() if line.strip()]
    stderr_lines = [line for line in proc.stderr.splitlines() if line.strip()]
    payload = parse_cli_tool_payload(stdout_lines)
    temp_home.cleanup()
    return {
        "returncode": proc.returncode,
        "stdout": stdout_lines,
        "stderr": stderr_lines,
        "payload": payload,
    }


def build_requests(project_root: Path, fixture: dict[str, Any], impl: str) -> tuple[list[dict[str, Any]], dict[str, str]]:
    project_name = fixture.get("project", "")
    project_path = normalize_path_for_manifest(str(project_root))
    c_project_name = normalize_project_name_for_c(project_path)

    tool_ctx = {
        "project": project_name,
        "c_project": c_project_name,
        "project_path": project_path,
    }

    requests = [
        {
            "request": {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {},
            },
            "compare_key": None,
        },
        {
            "request": {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": {},
            },
            "compare_key": "tools_list",
        },
        {
            "request": {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "index_repository",
                    "arguments": {"repo_path": project_path},
                },
            },
            "compare_key": "index_repository",
        },
    ]

    tool_id = 4
    assertions = fixture.get("assertions", {})
    contract_checks = fixture.get("contract_checks", {})

    for check in contract_checks.get("initialize", []):
        params = expand_contract_value(check.get("params", {}), impl, tool_ctx)
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "initialize",
                    "params": params,
                },
                "compare_key": "initialize_contract",
                "assertion": check,
            }
        )
        tool_id += 1

    for assertion in assertions.get("get_graph_schema", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "get_graph_schema",
                        "arguments": args,
                    },
                },
                "compare_key": "get_graph_schema",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("index_status", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "index_status",
                        "arguments": args,
                    },
                },
                "compare_key": "index_status",
                "assertion": assertion,
            }
        )
        tool_id += 1

    # search_graph: the C API uses "label" while the Zig API uses "label_pattern",
    # so we translate one shared manifest contract into per-implementation request
    # shapes below. Because those request shapes differ intentionally, comparison is
    # assertion-level (expected nodes/results) rather than strict request or raw
    # payload identity.
    for assertion in assertions.get("search_graph", []):
        args = dict(assertion.get("args", {}))
        is_error_assertion = assertion.get("expect", {}).get("expect_error", False)
        if impl == "zig":
            args = {k: v for k, v in args.items() if k != "label"}
            if not is_error_assertion:
                args["project"] = project_name
            if "label" in assertion.get("args", {}):
                args["label_pattern"] = assertion["args"]["label"]
        else:
            args = {k: v for k, v in args.items() if k != "label_pattern"}
            if not is_error_assertion:
                args["project"] = c_project_name
            if "label" in assertion.get("args", {}):
                args["label"] = assertion["args"]["label"]
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "search_graph",
                        "arguments": args,
                    },
                },
                "compare_key": "search_graph",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("get_code_snippet", []):
        args = dict(assertion.get("args", {}))
        if "qualified_name" not in args:
            continue
        args.setdefault("project", project_name if impl == "zig" else c_project_name)
        if impl == "c":
            args["qualified_name"] = snippet_lookup_name(str(args["qualified_name"]))
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "get_code_snippet",
                        "arguments": args,
                    },
                },
                "compare_key": "get_code_snippet",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("query_graph", []):
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            args["project"] = project_name
        else:
            args["project"] = c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "query_graph",
                        "arguments": args,
                    },
                },
                "compare_key": "query_graph",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("trace_call_path", []):
        tool_name = "trace_path" if impl == "c" else "trace_call_path"
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            args["project"] = project_name
        else:
            args["project"] = c_project_name
            if "function_name" not in args:
                hint = args.pop("start_node_name_hint", "")
                if hint:
                    args["function_name"] = hint
            if args.get("direction") == "out":
                args["direction"] = "outbound"
            elif args.get("direction") == "in":
                args["direction"] = "inbound"
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": tool_name,
                        "arguments": args,
                    },
                },
                "compare_key": "trace_call_path",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("get_architecture", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "get_architecture",
                        "arguments": args,
                    },
                },
                "compare_key": "get_architecture",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("search_code", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "search_code",
                        "arguments": args,
                    },
                },
                "compare_key": "search_code",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("detect_changes", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "detect_changes",
                        "arguments": args,
                    },
                },
                "compare_key": "detect_changes",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for assertion in assertions.get("manage_adr", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "manage_adr",
                        "arguments": args,
                    },
                },
                "compare_key": "manage_adr",
                "assertion": assertion,
            }
        )
        tool_id += 1

    requests.append(
        {
            "request": {
                "jsonrpc": "2.0",
                "id": tool_id,
                "method": "tools/call",
                "params": {
                    "name": "list_projects",
                    "arguments": {},
                },
            },
            "compare_key": "list_projects",
        }
    )
    tool_id += 1

    # delete_project MUST be last: it removes the project from the store.
    for assertion in assertions.get("delete_project", []):
        args = dict(assertion.get("args", {}))
        args["project"] = project_name if impl == "zig" else c_project_name
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": "delete_project",
                        "arguments": args,
                    },
                },
                "compare_key": "delete_project",
                "assertion": assertion,
            }
        )
        tool_id += 1

    for check in contract_checks.get("tool_calls", []):
        args = expand_contract_value(check.get("arguments", {}), impl, tool_ctx)
        tool_name = str(check.get("name", ""))
        if impl == "c" and tool_name == "trace_call_path":
            tool_name = "trace_path"
        requests.append(
            {
                "request": {
                    "jsonrpc": "2.0",
                    "id": tool_id,
                    "method": "tools/call",
                    "params": {
                        "name": tool_name,
                        "arguments": args,
                    },
                },
                "compare_key": "contract_tool_call",
                "assertion": check,
            }
        )
        tool_id += 1

    return requests, tool_ctx


def canonical_error(payload):
    # type: (Any) -> Optional[Dict[str, Any]]
    """Extract a canonical error dict from a payload, or None if no error."""
    if isinstance(payload, str):
        return {"code": -1, "message": payload}
    if not isinstance(payload, dict):
        return None
    error = payload.get("__error__")
    if error is None:
        return None
    if isinstance(error, dict):
        return {
            "code": int(error.get("code", -1)),
            "message": str(error.get("message", "")),
        }
    return {"code": -1, "message": str(error)}


def check_assertions(tool_name: str, tool_payload: Any, assertions: list[dict[str, Any]]) -> list[str]:
    failures = []
    for assertion in assertions:
        expected = assertion.get("expect", {})

        # Handle expect_error assertions: verify the response was an error,
        # then skip all normal assertion checks for this assertion.
        if expected.get("expect_error"):
            err = canonical_error(tool_payload)
            if err is None:
                failures.append(
                    "%s expected error but got success payload" % tool_name
                )
            continue

        if tool_name == "tools_list":
            required = set(expected.get("required_tools", []))
            available = set(canonical_tools_list(tool_payload or {}))
            missing = sorted(required.difference(available))
            if missing:
                failures.append(f"tools_list missing {missing}")
            continue

        if tool_name == "index_repository":
            if not isinstance(tool_payload, dict):
                failures.append("index result missing")
                continue
            if "nodes_min" in expected and tool_payload.get("nodes", 0) < expected["nodes_min"]:
                failures.append(f"nodes {tool_payload.get('nodes', 0)} < {expected['nodes_min']}")
            if "edges_min" in expected and tool_payload.get("edges", 0) < expected["edges_min"]:
                failures.append(f"edges {tool_payload.get('edges', 0)} < {expected['edges_min']}")
            continue

        if tool_name == "search_graph":
            required = set(expected.get("required_names", []))
            nodes = canonical_search_nodes(tool_payload or {})
            names = {node.get("name") for node in nodes}
            missing = sorted(required.difference(names))
            if missing:
                failures.append(f"search_graph missing {missing}")
            continue

        if tool_name == "query_graph":
            columns_expected = expected.get("columns")
            rows_min = expected.get("required_rows_min", 0)
            columns, rows = canonical_query(tool_payload or {})
            if columns_expected and list(columns) != columns_expected:
                failures.append(f"query columns {list(columns)} != {columns_expected}")
            if len(rows) < rows_min:
                failures.append(f"query rows {len(rows)} < {rows_min}")
            continue

        if tool_name == "trace_call_path":
            required_edges = set(expected.get("required_edge_types", []))
            edges = canonical_trace(tool_payload)
            edge_types = {edge[2] for edge in edges}
            missing = sorted(required_edges.difference(edge_types))
            if missing:
                failures.append(f"trace edges missing {missing}")
            continue

        if tool_name == "get_architecture":
            architecture = canonical_architecture(tool_payload or {})
            for key in ("required_node_labels", "required_edge_types"):
                expected_values = set(expected.get(key, []))
                actual_key = {
                    "required_node_labels": "node_labels",
                    "required_edge_types": "edge_types",
                }[key]
                available_values = set(architecture.get(actual_key, []))
                missing = sorted(expected_values.difference(available_values))
                if missing:
                    failures.append(f"{tool_name} missing {actual_key} {missing}")
            continue

        if tool_name == "search_code":
            results = canonical_search_code(tool_payload or {})
            if "total_results" in expected and results["total_results"] != expected["total_results"]:
                failures.append(
                    f"search_code total_results {results['total_results']} != {expected['total_results']}"
                )
            file_paths = {row["file_path"] for row in results["results"]}
            missing_files = sorted(set(expected.get("required_files", [])).difference(file_paths))
            if missing_files:
                failures.append(f"search_code missing files {missing_files}")
            for required_result in expected.get("required_results", []):
                if not isinstance(required_result, dict):
                    continue
                matched = False
                for result in results["results"]:
                    if required_result.get("name") and result["name"] != required_result["name"]:
                        continue
                    if required_result.get("file_path") and result["file_path"] != required_result["file_path"]:
                        continue
                    if required_result.get("label") and result["label"] != required_result["label"]:
                        continue
                    matched = True
                    break
                if not matched:
                    failures.append(f"search_code missing {required_result}")
            continue

        if tool_name == "detect_changes":
            changes = canonical_detect_changes(tool_payload or {})
            if "changed_count" in expected and changes["changed_count"] != expected["changed_count"]:
                failures.append(f"detect_changes changed_count {changes['changed_count']} != {expected['changed_count']}")
            required_files = set(expected.get("required_changed_files", []))
            missing_files = sorted(required_files.difference(changes["changed_files"]))
            if missing_files:
                failures.append(f"detect_changes missing changed_files {missing_files}")
            if expected.get("require_empty_impacted_symbols") and changes["impacted_symbols"]:
                failures.append("detect_changes impacted_symbols not empty")
            continue

        if tool_name == "manage_adr":
            adr_payload = canonical_manage_adr(tool_payload or {})
            if "status" in expected and adr_payload["status"] != expected["status"]:
                failures.append(f"manage_adr status {adr_payload['status']} != {expected['status']}")
            required_sections = expected.get("required_sections", [])
            missing_sections = [section for section in required_sections if section not in adr_payload["sections"]]
            if missing_sections:
                failures.append(f"manage_adr missing sections {missing_sections}")
            for fragment in expected.get("content_contains", []):
                if fragment not in adr_payload["content"]:
                    failures.append(f"manage_adr content missing {fragment}")
            continue

        if tool_name == "get_graph_schema":
            schema = canonical_graph_schema(tool_payload or {})
            for key in ("required_node_labels", "required_edge_types", "required_languages"):
                expected_values = set(expected.get(key, []))
                actual_key = {
                    "required_node_labels": "node_labels",
                    "required_edge_types": "edge_types",
                    "required_languages": "languages",
                }[key]
                available_values = set(schema.get(actual_key, []))
                missing = sorted(expected_values.difference(available_values))
                if missing:
                    failures.append(f"get_graph_schema missing {actual_key} {missing}")
            continue

        if tool_name == "get_code_snippet":
            snippet = canonical_code_snippet(tool_payload or {})
            if expected.get("has_source") and not snippet["source"]:
                failures.append("get_code_snippet source is empty")
            for fragment in expected.get("source_contains", []):
                if fragment not in snippet["source"]:
                    failures.append(f"get_code_snippet source missing '{fragment}'")
            continue

        if tool_name == "index_status":
            status = canonical_index_status(tool_payload or {})
            if "status" in expected and status["status"] != expected["status"]:
                failures.append(f"index_status status '{status['status']}' != '{expected['status']}'")
            continue

        if tool_name == "delete_project":
            result = canonical_delete_project(tool_payload or {})
            if not result["deleted"]:
                # Also accept no JSON-RPC error as success
                if isinstance(tool_payload, dict) and "__error__" in tool_payload:
                    failures.append(f"delete_project returned error: {tool_payload['__error__']}")
                elif not result["deleted"]:
                    failures.append("delete_project did not indicate success")
            continue

        if tool_name == "list_projects":
            entries = canonical_list_projects(tool_payload or {})
            if len(entries) == 0:
                failures.append("list_projects empty")
            required_names = set(expected.get("required_names", []))
            if required_names:
                available_names = {entry.get("name", "") for entry in entries}
                missing = sorted(required_names.difference(available_names))
                if missing:
                    failures.append(f"list_projects missing projects {missing}")
            continue

    return failures


def build_contract_snapshot(
    fixture: Dict[str, Any],
    impl_results: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    contract_checks = fixture.get("contract_checks", {})
    if not contract_checks:
        return None

    impl_payloads = impl_results.get("tool", {})
    snapshot: Dict[str, Any] = {}

    initialize_checks = contract_checks.get("initialize", [])
    if initialize_checks:
        entries = impl_payloads.get("initialize_contract", [])
        cases = []
        for index, check in enumerate(initialize_checks):
            payload = entries[index]["payload"] if index < len(entries) else {}
            cases.append(
                {
                    "label": str(check.get("label", f"initialize_{index}")),
                    "requested_protocol_version": str(check.get("params", {}).get("protocolVersion", "")),
                    "selected_protocol_version": canonical_initialize_result(payload).get("protocolVersion", ""),
                }
            )
        snapshot["initialize"] = cases

    tools_list_check = contract_checks.get("tools_list", {})
    if tools_list_check:
        tl_entries = impl_payloads.get("tools_list", [])
        tl_payload = tl_entries[0]["payload"] if tl_entries else {}
        tool_snapshot: Dict[str, Any] = {}
        if "tools" in tools_list_check:
            tool_snapshot["tools"] = canonical_tools_list(tl_payload)
        requested_schemas = tools_list_check.get("tool_schemas", {})
        if requested_schemas:
            available_schemas = canonical_tool_schema_contract(tl_payload)
            selected: Dict[str, Any] = {}
            for tool_name, requested_schema in requested_schemas.items():
                selected[tool_name] = select_tool_schema_fields(
                    available_schemas.get(str(tool_name), {}),
                    requested_schema,
                )
            tool_snapshot["tool_schemas"] = selected
        snapshot["tools_list"] = tool_snapshot

    tool_call_checks = contract_checks.get("tool_calls", [])
    if tool_call_checks:
        entries = impl_payloads.get("contract_tool_call", [])
        cases = []
        for index, check in enumerate(tool_call_checks):
            payload = entries[index]["payload"] if index < len(entries) else {}
            cases.append(
                {
                    "label": str(check.get("label", f"tool_call_{index}")),
                    "name": str(check.get("name", "")),
                    "result": canonical_contract_tool_result(payload),
                }
            )
        snapshot["tool_calls"] = cases

    cli_call_checks = contract_checks.get("cli_calls", [])
    if cli_call_checks:
        entries = impl_results.get("cli_contract", [])
        cases = []
        for index, check in enumerate(cli_call_checks):
            payload = entries[index]["payload"] if index < len(entries) else {}
            cases.append(
                {
                    "label": str(check.get("label", f"cli_call_{index}")),
                    "name": str(check.get("name", "")),
                    "result": canonical_contract_tool_result(payload),
                }
            )
        snapshot["cli_calls"] = cases

    return snapshot


def build_golden_snapshot(
    fixture: Dict[str, Any],
    zig_results: Dict[str, Any],
    assertions: Dict[str, Any],
) -> Dict[str, Any]:
    """Build a golden snapshot dict from Zig canonical outputs for one fixture."""
    fixture_id = fixture.get("id", fixture.get("project", "unknown"))
    impl_payloads = zig_results.get("tool", {})
    snapshot = {"fixture_id": fixture_id}  # type: Dict[str, Any]

    # tools_list
    tl_entries = impl_payloads.get("tools_list", [])
    if tl_entries:
        snapshot["tools_list"] = canonical_tools_list(tl_entries[0]["payload"])
    else:
        snapshot["tools_list"] = []

    # search_graph
    sg_entries = impl_payloads.get("search_graph", [])
    snapshot["search_graph"] = [canonical_search_nodes(e["payload"]) for e in sg_entries]

    # query_graph - store as JSON-safe dicts (tuples become lists)
    qg_entries = impl_payloads.get("query_graph", [])
    qg_list = []  # type: List[Dict[str, Any]]
    for e in qg_entries:
        columns, rows = canonical_query(e["payload"])
        qg_list.append({"columns": list(columns), "rows": sorted([list(row) for row in rows])})
    snapshot["query_graph"] = qg_list

    # trace_call_path - store as lists of [source, target, type]
    tc_entries = impl_payloads.get("trace_call_path", [])
    snapshot["trace_call_path"] = [
        [list(edge) for edge in canonical_trace(e["payload"])]
        for e in tc_entries
    ]

    # get_architecture
    ga_entries = impl_payloads.get("get_architecture", [])
    snapshot["get_architecture"] = [canonical_architecture(e["payload"]) for e in ga_entries]

    # search_code
    sc_entries = impl_payloads.get("search_code", [])
    snapshot["search_code"] = [canonical_search_code(e["payload"]) for e in sc_entries]

    # detect_changes - store count only (output is git-state-dependent)
    dc_entries = impl_payloads.get("detect_changes", [])
    snapshot["detect_changes_count"] = len(dc_entries)

    # manage_adr
    ma_entries = impl_payloads.get("manage_adr", [])
    snapshot["manage_adr"] = [canonical_manage_adr(e["payload"]) for e in ma_entries]

    # get_graph_schema
    gs_entries = impl_payloads.get("get_graph_schema", [])
    snapshot["get_graph_schema"] = [canonical_graph_schema(e["payload"]) for e in gs_entries]

    # get_code_snippet
    cs_entries = impl_payloads.get("get_code_snippet", [])
    snapshot["get_code_snippet"] = [canonical_code_snippet(e["payload"]) for e in cs_entries]

    # index_status
    is_entries = impl_payloads.get("index_status", [])
    snapshot["index_status"] = [canonical_index_status(e["payload"]) for e in is_entries]

    # delete_project
    dp_entries = impl_payloads.get("delete_project", [])
    snapshot["delete_project"] = [canonical_delete_project(e["payload"]) for e in dp_entries]

    # list_projects - store project name only (root_path varies by machine)
    lp_entries = impl_payloads.get("list_projects", [])
    if lp_entries:
        projects = canonical_list_projects(lp_entries[0]["payload"])
        snapshot["list_projects"] = [p["name"] for p in projects]
    else:
        snapshot["list_projects"] = []

    # errors - capture canonical error responses for expect_error assertions
    errors_snapshot = {}  # type: Dict[str, List[Optional[Dict[str, Any]]]]
    for tool_key in ("query_graph", "get_code_snippet", "search_graph"):
        tool_assertions = assertions.get(tool_key, [])
        tool_entries = impl_payloads.get(tool_key, [])
        error_list = []  # type: List[Optional[Dict[str, Any]]]
        has_error_assertion = False
        for i, ta in enumerate(tool_assertions):
            if ta.get("expect", {}).get("expect_error"):
                has_error_assertion = True
                entry_payload = tool_entries[i]["payload"] if i < len(tool_entries) else {}
                error_list.append(canonical_error(entry_payload))
            else:
                error_list.append(None)
        if has_error_assertion:
            errors_snapshot[tool_key] = error_list
    if errors_snapshot:
        snapshot["errors"] = errors_snapshot

    # index_repository - store min thresholds from manifest assertions + actual counts
    index_assert = assertions.get("index_repository", {}).get("expect", {})
    idx_entries = impl_payloads.get("index_repository", [])
    nodes_actual = 0
    edges_actual = 0
    if idx_entries:
        idx_payload = idx_entries[0]["payload"]
        if isinstance(idx_payload, dict):
            nodes_actual = int(idx_payload.get("nodes", 0))
            edges_actual = int(idx_payload.get("edges", 0))
    snapshot["index_repository"] = {
        "nodes_min": int(index_assert.get("nodes_min", 0)),
        "edges_min": int(index_assert.get("edges_min", 0)),
        "nodes_actual": nodes_actual,
        "edges_actual": edges_actual,
    }

    contract_snapshot = build_contract_snapshot(fixture, zig_results)
    if contract_snapshot is not None:
        snapshot["contract_checks"] = contract_snapshot

    return snapshot


def compare_golden_snapshot(
    fixture: Dict[str, Any],
    zig_results: Dict[str, Any],
    golden: Dict[str, Any],
    assertions: Dict[str, Any],
) -> Tuple[List[str], List[str]]:
    """Compare Zig canonical outputs against a golden snapshot.

    Returns (mismatches, warnings) where mismatches cause failure and warnings are informational."""
    mismatches = []  # type: List[str]
    warnings = []  # type: List[str]
    current = build_golden_snapshot(fixture, zig_results, assertions)

    # tools_list
    if current["tools_list"] != golden.get("tools_list", []):
        current_set = set(current["tools_list"])
        golden_set = set(golden.get("tools_list", []))
        added = sorted(current_set - golden_set)
        removed = sorted(golden_set - current_set)
        mismatches.append(
            "tools_list: added=%s removed=%s" % (added, removed)
        )

    # search_graph
    current_sg = current["search_graph"]
    golden_sg = golden.get("search_graph", [])
    if len(current_sg) != len(golden_sg):
        mismatches.append(
            "search_graph: count %d vs golden %d" % (len(current_sg), len(golden_sg))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_sg, golden_sg)):
            if cur != gld:
                mismatches.append("search_graph[%d]: differs" % i)

    # query_graph
    current_qg = current["query_graph"]
    golden_qg = golden.get("query_graph", [])
    if len(current_qg) != len(golden_qg):
        mismatches.append(
            "query_graph: count %d vs golden %d" % (len(current_qg), len(golden_qg))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_qg, golden_qg)):
            if cur.get("columns") != gld.get("columns"):
                mismatches.append(
                    "query_graph[%d]: columns %s vs golden %s" % (
                        i, cur.get("columns"), gld.get("columns"))
                )
            else:
                cur_rows = sorted(cur.get("rows", []))
                gld_rows = sorted(gld.get("rows", []))
                if cur_rows != gld_rows:
                    added = sorted(set(tuple(r) for r in cur_rows) - set(tuple(r) for r in gld_rows))
                    removed = sorted(set(tuple(r) for r in gld_rows) - set(tuple(r) for r in cur_rows))
                    mismatches.append(
                        "query_graph[%d]: rows differ (added=%s removed=%s)" % (i, added, removed)
                    )

    # trace_call_path — removed edges are regressions (mismatch),
    # additional edges are better coverage (warning only).
    current_tc = current["trace_call_path"]
    golden_tc = golden.get("trace_call_path", [])
    if len(current_tc) != len(golden_tc):
        mismatches.append(
            "trace_call_path: count %d vs golden %d" % (len(current_tc), len(golden_tc))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_tc, golden_tc)):
            if cur != gld:
                cur_set = {tuple(e) for e in cur}
                gld_set = {tuple(e) for e in gld}
                added = sorted(cur_set - gld_set)
                removed = sorted(gld_set - cur_set)
                if removed:
                    detail = ["  - %s" % (r,) for r in removed]
                    detail += ["  + %s" % (a,) for a in added]
                    mismatches.append("trace_call_path[%d]: edges differ\n%s" % (i, "\n".join(detail)))
                elif added:
                    detail = ["  + %s" % (a,) for a in added]
                    warnings.append("trace_call_path[%d]: new edges found\n%s" % (i, "\n".join(detail)))

    # get_architecture
    current_ga = current["get_architecture"]
    golden_ga = golden.get("get_architecture", [])
    if len(current_ga) != len(golden_ga):
        mismatches.append(
            "get_architecture: count %d vs golden %d" % (len(current_ga), len(golden_ga))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_ga, golden_ga)):
            if cur != gld:
                cur_labels = set(cur.get("node_labels", []))
                gld_labels = set(gld.get("node_labels", []))
                cur_types = set(cur.get("edge_types", []))
                gld_types = set(gld.get("edge_types", []))
                added_labels = sorted(cur_labels - gld_labels)
                removed_labels = sorted(gld_labels - cur_labels)
                added_types = sorted(cur_types - gld_types)
                removed_types = sorted(gld_types - cur_types)
                mismatches.append(
                    "get_architecture[%d]: node_labels(added=%s removed=%s) edge_types(added=%s removed=%s)"
                    % (i, added_labels, removed_labels, added_types, removed_types)
                )

    # search_code
    current_sc = current["search_code"]
    golden_sc = golden.get("search_code", [])
    if len(current_sc) != len(golden_sc):
        mismatches.append(
            "search_code: count %d vs golden %d" % (len(current_sc), len(golden_sc))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_sc, golden_sc)):
            if cur != gld:
                detail = []  # type: List[str]
                cur_results = cur.get("results", [])
                gld_results = gld.get("results", [])
                cur_set = {(r.get("name", ""), r.get("file_path", ""), r.get("label", "")) for r in cur_results}
                gld_set = {(r.get("name", ""), r.get("file_path", ""), r.get("label", "")) for r in gld_results}
                for added in sorted(cur_set - gld_set):
                    detail.append("  + %s" % (added,))
                for removed in sorted(gld_set - cur_set):
                    detail.append("  - %s" % (removed,))
                if cur.get("total_results") != gld.get("total_results"):
                    detail.append("  total_results: %s vs golden %s" % (cur.get("total_results"), gld.get("total_results")))
                if detail:
                    mismatches.append("search_code[%d]: results differ\n%s" % (i, "\n".join(detail)))
                else:
                    mismatches.append("search_code[%d]: differs" % i)

    # detect_changes - only compare call count (output is git-state-dependent)
    current_dc_count = current["detect_changes_count"]
    golden_dc_count = golden.get("detect_changes_count", golden.get("detect_changes", []))
    if isinstance(golden_dc_count, list):
        golden_dc_count = len(golden_dc_count)
    if current_dc_count != golden_dc_count:
        mismatches.append(
            "detect_changes: count %d vs golden %d" % (current_dc_count, golden_dc_count)
        )

    # manage_adr
    current_ma = current["manage_adr"]
    golden_ma = golden.get("manage_adr", [])
    if len(current_ma) != len(golden_ma):
        mismatches.append(
            "manage_adr: count %d vs golden %d" % (len(current_ma), len(golden_ma))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_ma, golden_ma)):
            if cur != gld:
                detail = []  # type: List[str]
                if cur.get("status") != gld.get("status"):
                    detail.append("  status: '%s' vs golden '%s'" % (cur.get("status"), gld.get("status")))
                cur_sections = set(cur.get("sections", []))
                gld_sections = set(gld.get("sections", []))
                for added in sorted(cur_sections - gld_sections):
                    detail.append("  + section: %s" % added)
                for removed in sorted(gld_sections - cur_sections):
                    detail.append("  - section: %s" % removed)
                if cur.get("content") != gld.get("content"):
                    detail.append("  content differs (len %d vs golden %d)" % (
                        len(cur.get("content", "")), len(gld.get("content", ""))))
                if detail:
                    mismatches.append("manage_adr[%d]: differs\n%s" % (i, "\n".join(detail)))
                else:
                    mismatches.append("manage_adr[%d]: differs" % i)

    # get_graph_schema
    current_gs = current.get("get_graph_schema", [])
    golden_gs = golden.get("get_graph_schema", [])
    if len(current_gs) != len(golden_gs):
        mismatches.append(
            "get_graph_schema: count %d vs golden %d" % (len(current_gs), len(golden_gs))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_gs, golden_gs)):
            if cur != gld:
                cur_labels = set(cur.get("node_labels", []))
                gld_labels = set(gld.get("node_labels", []))
                cur_types = set(cur.get("edge_types", []))
                gld_types = set(gld.get("edge_types", []))
                cur_languages = set(cur.get("languages", []))
                gld_languages = set(gld.get("languages", []))
                added_labels = sorted(cur_labels - gld_labels)
                removed_labels = sorted(gld_labels - cur_labels)
                added_types = sorted(cur_types - gld_types)
                removed_types = sorted(gld_types - cur_types)
                added_languages = sorted(cur_languages - gld_languages)
                removed_languages = sorted(gld_languages - cur_languages)
                mismatches.append(
                    "get_graph_schema[%d]: node_labels(added=%s removed=%s) edge_types(added=%s removed=%s) languages(added=%s removed=%s)"
                    % (
                        i,
                        added_labels,
                        removed_labels,
                        added_types,
                        removed_types,
                        added_languages,
                        removed_languages,
                    )
                )

    # get_code_snippet
    current_cs = current.get("get_code_snippet", [])
    golden_cs = golden.get("get_code_snippet", [])
    if len(current_cs) != len(golden_cs):
        mismatches.append(
            "get_code_snippet: count %d vs golden %d" % (len(current_cs), len(golden_cs))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_cs, golden_cs)):
            if cur != gld:
                diffs = []
                if cur.get("qualified_name") != gld.get("qualified_name"):
                    diffs.append("qualified_name: '%s' vs '%s'" % (cur.get("qualified_name"), gld.get("qualified_name")))
                if cur.get("file_path") != gld.get("file_path"):
                    diffs.append("file_path: '%s' vs '%s'" % (cur.get("file_path"), gld.get("file_path")))
                if cur.get("source") != gld.get("source"):
                    diffs.append("source differs (len %d vs %d)" % (len(cur.get("source", "")), len(gld.get("source", ""))))
                mismatches.append("get_code_snippet[%d]: %s" % (i, "; ".join(diffs) if diffs else "differs"))

    # index_status
    current_is = current.get("index_status", [])
    golden_is = golden.get("index_status", [])
    if len(current_is) != len(golden_is):
        mismatches.append(
            "index_status: count %d vs golden %d" % (len(current_is), len(golden_is))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_is, golden_is)):
            if cur != gld:
                mismatches.append(
                    "index_status[%d]: status '%s' vs golden '%s'" % (i, cur.get("status"), gld.get("status"))
                )

    # delete_project
    current_dp = current.get("delete_project", [])
    golden_dp = golden.get("delete_project", [])
    if len(current_dp) != len(golden_dp):
        mismatches.append(
            "delete_project: count %d vs golden %d" % (len(current_dp), len(golden_dp))
        )
    else:
        for i, (cur, gld) in enumerate(zip(current_dp, golden_dp)):
            if cur != gld:
                mismatches.append(
                    "delete_project[%d]: deleted=%s vs golden deleted=%s" % (i, cur.get("deleted"), gld.get("deleted"))
                )

    # list_projects - compare names only
    current_lp = current["list_projects"]
    golden_lp = golden.get("list_projects", [])
    if current_lp != golden_lp:
        mismatches.append(
            "list_projects: %s vs golden %s" % (current_lp, golden_lp)
        )

    if current.get("contract_checks") != golden.get("contract_checks"):
        mismatches.append("contract_checks: differs")

    # errors - compare error responses for expect_error assertions
    current_errors = current.get("errors", {})
    golden_errors = golden.get("errors", {})
    all_error_keys = sorted(set(list(current_errors.keys()) + list(golden_errors.keys())))
    for tool_key in all_error_keys:
        cur_err_list = current_errors.get(tool_key, [])
        gld_err_list = golden_errors.get(tool_key, [])
        if len(cur_err_list) != len(gld_err_list):
            mismatches.append(
                "errors[%s]: count %d vs golden %d" % (tool_key, len(cur_err_list), len(gld_err_list))
            )
        else:
            for i, (cur_err, gld_err) in enumerate(zip(cur_err_list, gld_err_list)):
                # Both None means this index was not an error assertion - skip
                if cur_err is None and gld_err is None:
                    continue
                # One is None and the other is not
                if (cur_err is None) != (gld_err is None):
                    mismatches.append(
                        "errors[%s][%d]: error=%s vs golden error=%s" % (
                            tool_key, i,
                            "present" if cur_err else "absent",
                            "present" if gld_err else "absent",
                        )
                    )
                    continue
                # Both present - compare. Only warn on message difference (codes matter more).
                if cur_err.get("code") != gld_err.get("code"):
                    mismatches.append(
                        "errors[%s][%d]: code %s vs golden %s" % (
                            tool_key, i, cur_err.get("code"), gld_err.get("code"))
                    )
                elif cur_err.get("message") != gld_err.get("message"):
                    warnings.append(
                        "errors[%s][%d]: message differs (non-fatal)" % (tool_key, i)
                    )

    # index_repository - check zig output meets min thresholds from golden
    golden_idx = golden.get("index_repository", {})
    idx_entries = zig_results.get("tool", {}).get("index_repository", [])
    if idx_entries:
        idx_payload = idx_entries[0]["payload"]
        nodes = int(idx_payload.get("nodes", 0)) if isinstance(idx_payload, dict) else 0
        edges = int(idx_payload.get("edges", 0)) if isinstance(idx_payload, dict) else 0
        nodes_min = int(golden_idx.get("nodes_min", 0))
        edges_min = int(golden_idx.get("edges_min", 0))
        if nodes < nodes_min:
            mismatches.append("index_repository: nodes %d < min %d" % (nodes, nodes_min))
        if edges < edges_min:
            mismatches.append("index_repository: edges %d < min %d" % (edges, edges_min))
        # Warn (non-failing) if actual counts dropped >20% from golden actuals
        golden_nodes_actual = int(golden_idx.get("nodes_actual", 0))
        golden_edges_actual = int(golden_idx.get("edges_actual", 0))
        if golden_nodes_actual > 0 and nodes < golden_nodes_actual * 0.8:
            warnings.append(
                "index_repository: WARN nodes %d dropped >20%% from golden actual %d"
                % (nodes, golden_nodes_actual)
            )
        if golden_edges_actual > 0 and edges < golden_edges_actual * 0.8:
            warnings.append(
                "index_repository: WARN edges %d dropped >20%% from golden actual %d"
                % (edges, golden_edges_actual)
            )

    return mismatches, warnings


def main() -> None:
    manifest_path = Path(sys.argv[1])
    root = Path(sys.argv[2]).resolve()
    c_bin = Path(sys.argv[3]) if sys.argv[3] else None
    zig_bin = Path(sys.argv[4])
    report_dir = Path(sys.argv[5]).resolve()
    mode = sys.argv[6] if len(sys.argv) > 6 else "compare"
    golden_dir = Path(sys.argv[7]) if len(sys.argv) > 7 else None
    report_dir.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(manifest_path.read_text())

    # Dispatch based on mode
    if mode in ("zig-only", "update-golden"):
        run_golden_mode(manifest, root, zig_bin, report_dir, mode, golden_dir)
        return

    # Default: compare mode (original behavior)
    assert c_bin is not None, "C binary required in compare mode"
    run_compare_mode(manifest, root, c_bin, zig_bin, report_dir)


def run_golden_mode(
    manifest: Dict[str, Any],
    root: Path,
    zig_bin: Path,
    report_dir: Path,
    mode: str,
    golden_dir: Optional[Path],
) -> None:
    """Run zig-only or update-golden mode."""
    assert golden_dir is not None, "golden_dir required for zig-only/update-golden modes"
    golden_dir.mkdir(parents=True, exist_ok=True)

    all_mismatches = []  # type: List[Dict[str, Any]]
    fixture_count = 0
    updated_count = 0

    for fixture in manifest.get("fixtures", []):
        fixture_id = fixture.get("id", fixture.get("project", "unknown"))
        assertions = fixture.get("assertions", {})
        contract_checks = fixture.get("contract_checks", {})
        contract_checks = fixture.get("contract_checks", {})
        fixture_count += 1

        prepared_root, tempdir = prepare_fixture_project(root, fixture)
        try:
            # Only run Zig
            requests, tool_ctx = build_requests(prepared_root, fixture, "zig")
            try:
                zig_results = call_mcp_sequence(str(zig_bin), str(prepared_root), requests, "zig")
                zig_results["tool_ctx"] = tool_ctx
                contract_checks = fixture.get("contract_checks", {})
                cli_calls = contract_checks.get("cli_calls", [])
                if cli_calls:
                    zig_results["cli_contract"] = [
                        run_cli_tool(
                            str(zig_bin),
                            str(prepared_root),
                            "zig",
                            str(check.get("name", "")),
                            expand_contract_value(check.get("arguments", {}), "zig", tool_ctx),
                        )
                        for check in cli_calls
                    ]
            except Exception as err:
                print("ERROR: fixture %s zig failed: %s" % (fixture_id, err))
                all_mismatches.append({"fixture": fixture_id, "error": str(err)})
                continue

            # Run assertion checks on Zig output (same as compare mode)
            impl_payloads = zig_results.get("tool", {})
            index_payload = (impl_payloads.get("index_repository") or [{"payload": {}}])[0]["payload"]
            index_assertions = assertions.get("index_repository", {})
            if index_assertions:
                failures = check_assertions("index_repository", index_payload, [index_assertions])
                if failures:
                    print("  WARN: %s index_repository assertion failures: %s" % (fixture_id, failures))

            golden_path = golden_dir / ("%s.json" % fixture_id)

            if mode == "update-golden":
                snapshot = build_golden_snapshot(fixture, zig_results, assertions)
                golden_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")
                updated_count += 1
                print("  updated: %s" % golden_path)

            elif mode == "zig-only":
                if not golden_path.exists():
                    print("FAIL: %s golden snapshot missing: %s" % (fixture_id, golden_path))
                    all_mismatches.append({
                        "fixture": fixture_id,
                        "error": "golden snapshot missing: %s" % golden_path,
                    })
                    continue

                golden = json.loads(golden_path.read_text())
                diffs, warns = compare_golden_snapshot(fixture, zig_results, golden, assertions)
                if diffs:
                    print("FAIL: %s" % fixture_id)
                    for diff in diffs:
                        print("  - %s" % diff)
                    for warn in warns:
                        print("  ~ %s" % warn)
                    all_mismatches.append({
                        "fixture": fixture_id,
                        "mismatches": diffs,
                        "warnings": warns,
                    })
                else:
                    if warns:
                        print("PASS: %s (with warnings)" % fixture_id)
                        for warn in warns:
                            print("  ~ %s" % warn)
                    else:
                        print("PASS: %s" % fixture_id)
        finally:
            if tempdir is not None:
                tempdir.cleanup()

    # Write summary report
    out_json = report_dir / "interop_golden_report.json"
    report = {
        "mode": mode,
        "fixtures": fixture_count,
        "mismatches": all_mismatches,
    }  # type: Dict[str, Any]

    if mode == "update-golden":
        report["updated"] = updated_count
        print("\nGolden snapshots updated: %d/%d" % (updated_count, fixture_count))
    else:
        report["failures"] = len(all_mismatches)
        print("\nGolden comparison: %d/%d passed" % (fixture_count - len(all_mismatches), fixture_count))

    out_json.write_text(json.dumps(report, indent=2))
    print("wrote report: %s" % out_json)

    if mode == "zig-only" and all_mismatches:
        sys.exit(1)


def run_compare_mode(
    manifest: Dict[str, Any],
    root: Path,
    c_bin: Path,
    zig_bin: Path,
    report_dir: Path,
) -> None:
    """Original compare mode: Zig vs C."""
    report = {
        "manifest": str(root / "testdata" / "interop" / "manifest.json"),
        "fixtures": {},
        "mismatches": [],
        "checks": {},
    }  # type: Dict[str, Any]

    for fixture in manifest.get("fixtures", []):
        fixture_id = fixture.get("id", fixture.get("project", "unknown"))
        assertions = fixture.get("assertions", {})
        contract_checks = fixture.get("contract_checks", {})

        results = {
            "zig": {},
            "c": {},
            "request_count": 0,
            "comparison": {},
            "errors": [],
        }  # type: Dict[str, Any]

        prepared_root, tempdir = prepare_fixture_project(root, fixture)
        try:
            for impl in ("zig", "c"):
                bin_path = str(zig_bin if impl == "zig" else c_bin)
                requests, tool_ctx = build_requests(prepared_root, fixture, impl)
                results["request_count"] = len(requests)
                try:
                    tool_results = call_mcp_sequence(bin_path, str(prepared_root), requests, impl)
                    tool_results["tool_ctx"] = tool_ctx
                    cli_calls = contract_checks.get("cli_calls", [])
                    if cli_calls:
                        tool_results["cli_contract"] = [
                            run_cli_tool(
                                bin_path,
                                str(prepared_root),
                                impl,
                                str(check.get("name", "")),
                                expand_contract_value(check.get("arguments", {}), impl, tool_ctx),
                            )
                            for check in cli_calls
                        ]
                    results[impl] = tool_results
                except Exception as err:
                    results["errors"].append(f"{impl}: {err}")
                    continue

                impl_payloads = results[impl]["tool"]

                # Normalize and validate index output if requested.
                index_payload = (impl_payloads.get("index_repository") or [{"payload": {}}])[0]["payload"]
                index_assertions = assertions.get("index_repository", {})
                if index_assertions:
                    failures = check_assertions("index_repository", index_payload, [index_assertions])
                    if failures:
                        results[impl].setdefault("assertion_failures", []).append(
                            {"tool": "index_repository", "failures": failures}
                        )

                tools_list_payload = (impl_payloads.get("tools_list") or [{"payload": {}}])[0]["payload"]
                tools_list_assertions = [
                    {
                        "expect": {
                            "required_tools": SHARED_TOOL_NAMES,
                        }
                    }
                ]
                failures = check_assertions("tools_list", tools_list_payload, tools_list_assertions)
                if failures:
                    results[impl].setdefault("assertion_failures", []).append(
                        {"tool": "tools_list", "failures": failures}
                    )

                for scope_tool in ("search_graph", "query_graph", "trace_call_path", "get_architecture", "search_code", "detect_changes", "manage_adr", "get_graph_schema", "get_code_snippet", "index_status", "delete_project"):
                    assertion_key = scope_tool
                    for index, assertion in enumerate(assertions.get(assertion_key, [])):
                        entries = impl_payloads.get(scope_tool) or []
                        payload = entries[index]["payload"] if index < len(entries) else {"__missing__": True}
                        failures = check_assertions(scope_tool, payload, [assertion])
                        if failures:
                            results[impl].setdefault("assertion_failures", []).append(
                                {"tool": scope_tool, "assert": assertion, "failures": failures}
                            )
        finally:
            if tempdir is not None:
                tempdir.cleanup()

            # list_projects is global and used as fixture-scoped indexing signal.
            list_payload = (impl_payloads.get("list_projects") or [{"payload": {}}])[0]["payload"]
            canonical_projects = canonical_list_projects(list_payload)
            fixture_project_name = fixture.get("project") if impl == "zig" else tool_ctx["c_project"]
            selected = [p for p in canonical_projects if p["name"] == fixture_project_name]
            if selected:
                results[impl]["fixture_project"] = selected[0]
            else:
                results[impl]["fixture_project"] = {}
            if not selected:
                results[impl].setdefault("assertion_failures", []).append(
                    {
                        "tool": "list_projects",
                        "failures": [f"fixture project '{fixture_project_name}' not found in list_projects"],
                    }
                )

        # Compare canonical outputs across CUT and C.
        def get_entries(impl_name: str, tool_name: str) -> list:
            return results[impl_name].get("tool", {}).get(tool_name, [])

        comparisons = {}
        for scope in (
            "tools_list",
            "search_graph",
            "query_graph",
            "trace_call_path",
            "get_architecture",
            "search_code",
            "detect_changes",
            "manage_adr",
            "get_graph_schema",
            "get_code_snippet",
            "index_status",
            "delete_project",
            "list_projects",
            "index_repository",
            "contract_checks",
        ):
            if scope == "tools_list":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    expected_tools = sorted(SHARED_TOOL_NAMES)
                    z_tools = set(canonical_tools_list(z_entries[0]["payload"]))
                    c_tools = set(canonical_tools_list(c_entries[0]["payload"]))
                    z_missing = sorted(set(expected_tools).difference(z_tools))
                    c_missing = sorted(set(expected_tools).difference(c_tools))
                    if z_missing or c_missing:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "shared_tools"}
                        )
                        comparisons[scope] = {
                            "status": "mismatch",
                            "required_tools": expected_tools,
                            "zig_missing": z_missing,
                            "c_missing": c_missing,
                        }
                    else:
                        comparisons[scope] = {"status": "match", "count": len(expected_tools)}

            if scope == "search_graph":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    has_diagnostic = False
                    for index, assertion in enumerate(assertions.get("search_graph", [])):
                        z_nodes = canonical_search_nodes(z_entries[index]["payload"])
                        c_nodes = canonical_search_nodes(c_entries[index]["payload"])
                        required = sorted(set(assertion.get("expect", {}).get("required_names", [])))
                        z_names = {node["name"] for node in z_nodes}
                        c_names = {node["name"] for node in c_nodes}
                        z_missing = sorted(set(required).difference(z_names))
                        c_missing = sorted(set(required).difference(c_names))
                        case = {
                            "required_names": required,
                            "zig_missing": z_missing,
                            "c_missing": c_missing,
                        }
                        if z_missing != c_missing:
                            has_mismatch = True
                        elif z_missing:
                            has_diagnostic = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "search_nodes"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    elif has_diagnostic:
                        comparisons[scope] = {
                            "status": "diagnostic",
                            "note": "shared required-name gaps remain outside mismatch scoring when both implementations miss the same symbols",
                            "cases": cases,
                        }
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "query_graph":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    has_diagnostic = False
                    for index, assertion in enumerate(assertions.get("query_graph", [])):
                        expected = assertion.get("expect", {})
                        exact_compare = bool(expected.get("exact_compare", False))
                        preserve_order = bool(expected.get("preserve_order", exact_compare))
                        z_case = canonical_query(z_entries[index]["payload"], preserve_order=preserve_order)
                        c_case = canonical_query(c_entries[index]["payload"], preserve_order=preserve_order)
                        z_failures = check_assertions("query_graph", z_entries[index]["payload"], [assertion])
                        c_failures = check_assertions("query_graph", c_entries[index]["payload"], [assertion])
                        case = {
                            "zig": z_case,
                            "c": c_case,
                            "zig_failures": z_failures,
                            "c_failures": c_failures,
                        }
                        if exact_compare:
                            if z_failures or c_failures or z_case != c_case:
                                has_mismatch = True
                        elif z_failures != c_failures:
                            has_mismatch = True
                        elif z_case != c_case:
                            has_diagnostic = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "query_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    elif has_diagnostic:
                        comparisons[scope] = {
                            "status": "diagnostic",
                            "note": "both implementations satisfy the shared query contract, but row sets still differ outside the scored floor",
                            "cases": cases,
                        }
                    else:
                        comparisons[scope] = {"status": "match"}

            if scope == "trace_call_path":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("trace_call_path", [])):
                        if assertion.get("expect", {}).get("exact_compare"):
                            z_contract = canonical_trace_contract(z_entries[index]["payload"])
                            c_contract = canonical_trace_contract(c_entries[index]["payload"])
                            case = {
                                "zig": z_contract,
                                "c": c_contract,
                                "exact_compare": True,
                            }
                            if z_contract != c_contract:
                                has_mismatch = True
                            cases.append(case)
                            continue
                        required = sorted(set(assertion.get("expect", {}).get("required_edge_types", [])))
                        z_types = sorted({edge[2] for edge in canonical_trace(z_entries[index]["payload"])})
                        c_types = sorted({edge[2] for edge in canonical_trace(c_entries[index]["payload"])})
                        z_missing = sorted(set(required).difference(z_types))
                        c_missing = sorted(set(required).difference(c_types))
                        case = {
                            "required_edge_types": required,
                            "zig_missing": z_missing,
                            "c_missing": c_missing,
                            "zig_types": z_types,
                            "c_types": c_types,
                        }
                        if z_missing or c_missing:
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "trace_edges"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "get_architecture":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    has_diagnostic = False
                    for index, assertion in enumerate(assertions.get("get_architecture", [])):
                        expected = assertion.get("expect", {})
                        z_arch = canonical_architecture(z_entries[index]["payload"])
                        c_arch = canonical_architecture(c_entries[index]["payload"])
                        if expected.get("exact_compare"):
                            case = {
                                "zig": z_arch,
                                "c": c_arch,
                                "exact_compare": True,
                            }
                            if z_arch != c_arch:
                                if expected.get("compare_mode") == "diagnostic":
                                    has_diagnostic = True
                                else:
                                    has_mismatch = True
                            cases.append(case)
                            continue
                        case = {}
                        for expected_key, actual_key in (
                            ("required_node_labels", "node_labels"),
                            ("required_edge_types", "edge_types"),
                        ):
                            required = sorted(set(expected.get(expected_key, [])))
                            z_missing = sorted(set(required).difference(z_arch.get(actual_key, [])))
                            c_missing = sorted(set(required).difference(c_arch.get(actual_key, [])))
                            case[expected_key] = required
                            case[f"zig_missing_{actual_key}"] = z_missing
                            case[f"c_missing_{actual_key}"] = c_missing
                            if z_missing or c_missing:
                                has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "architecture_contract"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    elif has_diagnostic:
                        comparisons[scope] = {
                            "status": "diagnostic",
                            "note": "exact architecture aspect payloads still differ across implementations",
                            "cases": cases,
                        }
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "search_code":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("search_code", [])):
                        expected = assertion.get("expect", {})
                        if expected.get("exact_compare"):
                            z_rows = canonical_search_code(z_entries[index]["payload"])
                            c_rows = canonical_search_code(c_entries[index]["payload"])
                            case = {
                                "zig": z_rows,
                                "c": c_rows,
                                "exact_compare": True,
                            }
                            if z_rows != c_rows:
                                has_mismatch = True
                            cases.append(case)
                            continue
                        expected_rows = expected.get("required_results", [])
                        expected_files = expected.get("required_files", [])
                        z_rows = canonical_search_code(z_entries[index]["payload"])
                        c_rows = canonical_search_code(c_entries[index]["payload"])
                        same_shape = z_rows == c_rows
                        case_rows = []
                        for expected_row in expected_rows:
                            z_match = any(
                                row["name"] == expected_row.get("name", row["name"])
                                and row["file_path"] == expected_row.get("file_path", row["file_path"])
                                and row["label"] == expected_row.get("label", row["label"])
                                for row in z_rows["results"]
                            )
                            c_match = any(
                                row["name"] == expected_row.get("name", row["name"])
                                and row["file_path"] == expected_row.get("file_path", row["file_path"])
                                and row["label"] == expected_row.get("label", row["label"])
                                for row in c_rows["results"]
                            )
                            case_rows.append(
                                {
                                    "expected": expected_row,
                                    "zig_match": z_match,
                                    "c_match": c_match,
                                }
                            )
                            if not z_match or not c_match:
                                has_mismatch = True
                        z_files = sorted({row["file_path"] for row in z_rows["results"]})
                        c_files = sorted({row["file_path"] for row in c_rows["results"]})
                        z_missing_files = sorted(set(expected_files).difference(z_files))
                        c_missing_files = sorted(set(expected_files).difference(c_files))
                        if z_missing_files or c_missing_files:
                            has_mismatch = True
                        if not same_shape:
                            has_mismatch = True
                        cases.append(
                            {
                                "required_results": case_rows,
                                "required_files": expected_files,
                                "zig_missing_files": z_missing_files,
                                "c_missing_files": c_missing_files,
                                "zig": z_rows,
                                "c": c_rows,
                            }
                        )
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "search_code_contract"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "detect_changes":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("detect_changes", [])):
                        expected = assertion.get("expect", {})
                        z_changes = canonical_detect_changes(z_entries[index]["payload"])
                        c_changes = canonical_detect_changes(c_entries[index]["payload"])
                        case = {
                            "expected": expected,
                            "zig": z_changes,
                            "c": c_changes,
                        }
                        if z_changes != c_changes:
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "detect_changes_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "manage_adr":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("manage_adr", [])):
                        z_payload = canonical_manage_adr(z_entries[index]["payload"])
                        c_payload = canonical_manage_adr(c_entries[index]["payload"])
                        case = {
                            "mode": assertion.get("args", {}).get("mode", "get"),
                            "zig": z_payload,
                            "c": c_payload,
                        }
                        if z_payload != c_payload:
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "adr_payload"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "get_graph_schema":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    has_diagnostic = False
                    for index, assertion in enumerate(assertions.get("get_graph_schema", [])):
                        expected = assertion.get("expect", {})
                        z_schema = canonical_graph_schema(z_entries[index]["payload"])
                        c_schema = canonical_graph_schema(c_entries[index]["payload"])
                        if expected.get("exact_compare"):
                            case = {
                                "zig": z_schema,
                                "c": c_schema,
                                "exact_compare": True,
                            }
                            if z_schema != c_schema:
                                if expected.get("compare_mode") == "diagnostic":
                                    has_diagnostic = True
                                else:
                                    has_mismatch = True
                            cases.append(case)
                            continue
                        case = {}  # type: Dict[str, Any]
                        for expected_key, actual_key in (
                            ("required_node_labels", "node_labels"),
                            ("required_edge_types", "edge_types"),
                        ):
                            required = sorted(set(expected.get(expected_key, [])))
                            z_missing = sorted(set(required).difference(z_schema.get(actual_key, [])))
                            c_missing = sorted(set(required).difference(c_schema.get(actual_key, [])))
                            case[expected_key] = required
                            case["zig_missing_%s" % actual_key] = z_missing
                            case["c_missing_%s" % actual_key] = c_missing
                            if z_missing or c_missing:
                                has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "graph_schema_contract"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    elif has_diagnostic:
                        comparisons[scope] = {
                            "status": "diagnostic",
                            "note": "exact schema payloads still differ because graph vocabulary is not yet fully aligned",
                            "cases": cases,
                        }
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "get_code_snippet":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    has_diagnostic = False
                    for index, assertion in enumerate(assertions.get("get_code_snippet", [])):
                        z_snippet = canonical_code_snippet(z_entries[index]["payload"])
                        c_snippet = canonical_code_snippet(c_entries[index]["payload"])
                        z_comparable = comparable_code_snippet(z_entries[index]["payload"])
                        c_comparable = comparable_code_snippet(c_entries[index]["payload"])
                        z_failures = check_assertions("get_code_snippet", z_entries[index]["payload"], [assertion])
                        c_failures = check_assertions("get_code_snippet", c_entries[index]["payload"], [assertion])
                        case = {
                            "zig": z_snippet,
                            "c": c_snippet,
                            "zig_comparable": z_comparable,
                            "c_comparable": c_comparable,
                            "zig_failures": z_failures,
                            "c_failures": c_failures,
                        }
                        if assertion.get("expect", {}).get("exact_compare"):
                            if z_failures or c_failures or z_comparable != c_comparable:
                                has_mismatch = True
                        elif z_failures != c_failures:
                            has_mismatch = True
                        elif z_comparable != c_comparable:
                            has_diagnostic = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "code_snippet_payload"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    elif has_diagnostic:
                        comparisons[scope] = {
                            "status": "diagnostic",
                            "note": "both implementations satisfy the snippet contract, but qualified-name/path metadata still differs outside the scored floor",
                            "cases": cases,
                        }
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "index_status":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("index_status", [])):
                        z_status = canonical_index_status(z_entries[index]["payload"])
                        c_status = canonical_index_status(c_entries[index]["payload"])
                        case = {
                            "zig": z_status,
                            "c": c_status,
                        }
                        if assertion.get("expect", {}).get("exact_compare"):
                            if z_status != c_status:
                                has_mismatch = True
                        elif z_status.get("status") != c_status.get("status"):
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "index_status_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "delete_project":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    for index, assertion in enumerate(assertions.get("delete_project", [])):
                        z_result = canonical_delete_project(z_entries[index]["payload"])
                        c_result = canonical_delete_project(c_entries[index]["payload"])
                        case = {
                            "zig": z_result,
                            "c": c_result,
                        }
                        if assertion.get("expect", {}).get("exact_compare"):
                            if z_result != c_result:
                                has_mismatch = True
                        elif z_result.get("deleted") != c_result.get("deleted"):
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "delete_project_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "list_projects":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries and not c_entries:
                    comparisons[scope] = {"status": "not_requested"}
                elif not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    cases = []
                    has_mismatch = False
                    zig_fixture_project_name = fixture.get("project")
                    c_fixture_project_name = results["c"].get("tool_ctx", {}).get("c_project", zig_fixture_project_name)
                    for index, assertion in enumerate(assertions.get("list_projects", [])):
                        z_projects = canonical_list_projects(z_entries[index]["payload"])
                        c_projects = canonical_list_projects(c_entries[index]["payload"])
                        if assertion.get("expect", {}).get("exact_compare"):
                            z_project = next((item for item in z_projects if item.get("name") == zig_fixture_project_name), None)
                            c_project = next((item for item in c_projects if item.get("name") == c_fixture_project_name), None)
                            case = {
                                "zig": {"root_path": (z_project or {}).get("root_path", "")},
                                "c": {"root_path": (c_project or {}).get("root_path", "")},
                                "exact_compare": True,
                            }
                            if case["zig"] != case["c"]:
                                has_mismatch = True
                            cases.append(case)
                        else:
                            z_project = next((item for item in z_projects if item.get("name") == zig_fixture_project_name), None)
                            c_project = next((item for item in c_projects if item.get("name") == c_fixture_project_name), None)
                            case = {
                                "zig": {"root_path": (z_project or {}).get("root_path", "")},
                                "c": {"root_path": (c_project or {}).get("root_path", "")},
                            }
                            if case["zig"] != case["c"]:
                                has_mismatch = True
                            cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "list_projects"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "index_repository":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    z = z_entries[0]["payload"]
                    c = c_entries[0]["payload"]
                    comparisons[scope] = {
                        "status": "diagnostic",
                        "note": "node and edge totals remain diagnostic-only until parity work defines stable expectations",
                        "zig": {"nodes": int(z.get("nodes", 0)), "edges": int(z.get("edges", 0))},
                        "c": {"nodes": int(c.get("nodes", 0)), "edges": int(c.get("edges", 0))},
                    }

            if scope == "contract_checks":
                if not contract_checks:
                    comparisons[scope] = {"status": "not_requested"}
                else:
                    z_contract = build_contract_snapshot(fixture, results["zig"])
                    c_contract = build_contract_snapshot(fixture, results["c"])
                    if z_contract is None or c_contract is None:
                        comparisons[scope] = {
                            "status": "missing",
                            "zig": z_contract is not None,
                            "c": c_contract is not None,
                        }
                    elif z_contract != c_contract:
                        if contract_checks.get("compare_mode") == "diagnostic":
                            comparisons[scope] = {
                                "status": "diagnostic",
                                "note": contract_checks.get("compare_note", "known tool-surface divergence"),
                                "zig": z_contract,
                                "c": c_contract,
                            }
                        else:
                            report["mismatches"].append(
                                {"fixture": fixture_id, "tool": scope, "category": "contract_checks"}
                            )
                            comparisons[scope] = {
                                "status": "mismatch",
                                "zig": z_contract,
                                "c": c_contract,
                            }
                    else:
                        comparisons[scope] = {"status": "match"}

        results["comparison"] = comparisons
        report["fixtures"][fixture_id] = results

    progress_fixture = next((fixture for fixture in manifest.get("fixtures", []) if fixture.get("id") == "python-parity"), None)
    if progress_fixture is not None:
        progress_path = str((root / progress_fixture.get("path", "")).resolve())
        zig_progress = run_cli_progress(str(zig_bin), progress_path, "zig")
        c_progress = run_cli_progress(str(c_bin), progress_path, "c")
        progress_check = {
            "zig": zig_progress,
            "c": c_progress,
        }
        if zig_progress["returncode"] != 0 or c_progress["returncode"] != 0:
            progress_check["status"] = "missing"
            report["mismatches"].append(
                {"fixture": "shared-cli-progress", "tool": "cli_progress", "category": "progress_command"}
            )
        elif zig_progress["progress"] != c_progress["progress"]:
            progress_check["status"] = "mismatch"
            report["mismatches"].append(
                {"fixture": "shared-cli-progress", "tool": "cli_progress", "category": "progress_contract"}
            )
        else:
            progress_check["status"] = "match"
        report["checks"]["cli_progress"] = progress_check

    out_json = report_dir / "interop_alignment_report.json"
    out_md = report_dir / "interop_alignment_report.md"

    out_json.write_text(json.dumps(report, indent=2))

    total_fixtures = len(report["fixtures"])
    total_matches = sum(1 for r in report["fixtures"].values() for cmp in r.get("comparison", {}).values() if isinstance(cmp, dict) and cmp.get("status") == "match")
    total_diagnostics = sum(1 for r in report["fixtures"].values() for cmp in r.get("comparison", {}).values() if isinstance(cmp, dict) and cmp.get("status") == "diagnostic")
    total_comparisons = sum(
        1
        for r in report["fixtures"].values()
        for cmp in r.get("comparison", {}).values()
        if isinstance(cmp, dict) and cmp.get("status") != "not_requested"
    )
    for check in report.get("checks", {}).values():
        if isinstance(check, dict) and check.get("status"):
            total_comparisons += 1
            if check["status"] == "match":
                total_matches += 1
    mismatch_count = len(report["mismatches"])

    lines = [
        "# Interop Alignment Baseline",
        "",
        f"- Fixtures: {total_fixtures}",
        f"- Comparisons: {total_comparisons}",
        f"- Strict matches: {total_matches}",
        f"- Diagnostic-only comparisons: {total_diagnostics}",
        f"- Mismatches: {mismatch_count}",
        "",
        "## Mismatch Summary",
    ]
    for mismatch in report["mismatches"]:
        fixture = mismatch["fixture"]
        tool = mismatch["tool"]
        category = mismatch["category"]
        lines.append(f"- {fixture}: {tool} ({category})")
    if not report["mismatches"]:
        lines.append("- none")
    if report.get("checks"):
        lines.extend(["", "## Extra Checks"])
        for check_name, check in report["checks"].items():
            lines.append(f"- {check_name}: {check.get('status', 'unknown')}")

    out_md.write_text("\n".join(lines) + "\n")
    print(f"wrote report: {out_json}")
    print(f"wrote report: {out_md}")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
PY
