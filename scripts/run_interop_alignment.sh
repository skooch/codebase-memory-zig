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


def canonical_query(payload: Any) -> tuple[tuple[str, ...], list[tuple[str, ...]]]:
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


def canonical_architecture(payload: Any) -> dict[str, list[str]]:
    if not isinstance(payload, dict):
        return {"node_labels": [], "edge_types": []}

    def collect_named(entries: Any, key: str) -> list[str]:
        if not isinstance(entries, list):
            return []
        out: list[str] = []
        for entry in entries:
            if isinstance(entry, dict) and entry.get(key):
                out.append(str(entry[key]))
        return sorted(set(out))

    return {
        "node_labels": collect_named(payload.get("node_labels"), "label"),
        "edge_types": collect_named(payload.get("edge_types"), "type"),
    }


def canonical_search_code(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"total_results": 0, "results": []}
    results = payload.get("results", [])
    if not isinstance(results, list):
        return {"total_results": 0, "results": []}
    normalized: list[dict[str, str]] = []
    for row in results:
        if not isinstance(row, dict):
            continue
        normalized.append(
            {
                "file_path": normalize_path_for_manifest(str(row.get("file_path", row.get("file", "")))),
                "name": str(row.get("name", row.get("node", ""))),
                "label": str(row.get("label", "")),
            }
        )
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


def canonical_graph_schema(payload: Any) -> dict[str, list[str]]:
    if not isinstance(payload, dict):
        return {"node_labels": [], "edge_types": []}
    node_labels = payload.get("node_labels", [])
    edge_types = payload.get("edge_types", [])
    if not isinstance(node_labels, list):
        node_labels = []
    if not isinstance(edge_types, list):
        edge_types = []
    return {
        "node_labels": sorted(str(l) for l in node_labels),
        "edge_types": sorted(str(t) for t in edge_types),
    }


def canonical_code_snippet(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"qualified_name": "", "source": "", "file_path": ""}
    return {
        "qualified_name": str(payload.get("qualified_name", "")),
        "source": str(payload.get("source", "")),
        "file_path": normalize_path_for_manifest(str(payload.get("file_path", ""))),
    }


def canonical_index_status(payload: Any) -> dict[str, str]:
    if not isinstance(payload, dict):
        return {"status": "unknown"}
    return {"status": str(payload.get("status", "unknown"))}


def canonical_delete_project(payload: Any) -> dict[str, bool]:
    if not isinstance(payload, dict):
        return {"deleted": False}
    deleted = (
        payload.get("status") == "deleted"
        or payload.get("success", False)
    )
    return {"deleted": bool(deleted)}


def send_rpc_request(process: subprocess.Popen[str], request: dict[str, Any]) -> tuple[dict[str, Any], str]:
    assert process.stdin is not None
    assert process.stdout is not None

    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()

    buffer = ""
    while True:
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
        if process.stdin is not None and not process.stdin.closed:
            process.stdin.close()
        if process.stdout is not None:
            remainder = process.stdout.read()
            if remainder:
                tool_results["stdout"].extend([line for line in remainder.splitlines() if line.strip()])
        if process.stderr is not None:
            stderr = process.stderr.read()
            if stderr:
                tool_results["stderr"] = stderr.splitlines()
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            raise
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


def run_cli_progress(bin_path: str, project_path: str, impl: str) -> dict[str, Any]:
    env = os.environ.copy()
    temp_home = tempfile.TemporaryDirectory(prefix=f"cbm-progress-{impl}-")
    env["HOME"] = temp_home.name
    env["CBM_CACHE_DIR"] = str(Path(temp_home.name) / ".cache" / "codebase-memory-zig")
    args = json.dumps({"project_path": project_path} if impl == "zig" else {"repo_path": project_path})
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


def build_requests(root: Path, fixture: dict[str, Any], impl: str) -> tuple[list[dict[str, Any]], dict[str, str]]:
    project_name = fixture.get("project", "")
    project_path = normalize_path_for_manifest(str(root / fixture.get("path", "")))
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
                    "arguments": (
                        {"project_path": project_path}
                        if impl == "zig"
                        else {"repo_path": project_path}
                    ),
                },
            },
            "compare_key": "index_repository",
        },
    ]

    tool_id = 4
    assertions = fixture.get("assertions", {})

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
    # so we translate the parameter name per-implementation below. Because the APIs
    # differ, search_graph comparison is assertion-level (checking expected nodes
    # appear in results) rather than raw output-level equality.
    for assertion in assertions.get("search_graph", []):
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            args = {k: v for k, v in args.items() if k != "label"}
            args["project"] = project_name
            if "label" in assertion.get("args", {}):
                args["label_pattern"] = assertion["args"]["label"]
        else:
            args = {k: v for k, v in args.items() if k != "label_pattern"}
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

    return requests, tool_ctx


def check_assertions(tool_name: str, tool_payload: Any, assertions: list[dict[str, Any]]) -> list[str]:
    failures = []
    for assertion in assertions:
        expected = assertion.get("expect", {})
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
            for key in ("required_node_labels", "required_edge_types"):
                expected_values = set(expected.get(key, []))
                actual_key = {
                    "required_node_labels": "node_labels",
                    "required_edge_types": "edge_types",
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
            continue

    return failures


def build_golden_snapshot(
    fixture_id: str,
    zig_results: Dict[str, Any],
    assertions: Dict[str, Any],
) -> Dict[str, Any]:
    """Build a golden snapshot dict from Zig canonical outputs for one fixture."""
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

    return snapshot


def compare_golden_snapshot(
    fixture_id: str,
    zig_results: Dict[str, Any],
    golden: Dict[str, Any],
    assertions: Dict[str, Any],
) -> Tuple[List[str], List[str]]:
    """Compare Zig canonical outputs against a golden snapshot.

    Returns (mismatches, warnings) where mismatches cause failure and warnings are informational."""
    mismatches = []  # type: List[str]
    warnings = []  # type: List[str]
    current = build_golden_snapshot(fixture_id, zig_results, assertions)

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

    # trace_call_path
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
                detail = []  # type: List[str]
                for added in sorted(cur_set - gld_set):
                    detail.append("  + %s" % (added,))
                for removed in sorted(gld_set - cur_set):
                    detail.append("  - %s" % (removed,))
                if detail:
                    mismatches.append("trace_call_path[%d]: edges differ\n%s" % (i, "\n".join(detail)))
                else:
                    mismatches.append("trace_call_path[%d]: differs" % i)

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
                added_labels = sorted(cur_labels - gld_labels)
                removed_labels = sorted(gld_labels - cur_labels)
                added_types = sorted(cur_types - gld_types)
                removed_types = sorted(gld_types - cur_types)
                mismatches.append(
                    "get_graph_schema[%d]: node_labels(added=%s removed=%s) edge_types(added=%s removed=%s)"
                    % (i, added_labels, removed_labels, added_types, removed_types)
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
        root_path = root / fixture.get("path", "")
        assertions = fixture.get("assertions", {})
        fixture_count += 1

        # Only run Zig
        requests, tool_ctx = build_requests(root, fixture, "zig")
        try:
            zig_results = call_mcp_sequence(str(zig_bin), str(root_path), requests, "zig")
            zig_results["tool_ctx"] = tool_ctx
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
            snapshot = build_golden_snapshot(fixture_id, zig_results, assertions)
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
            diffs, warns = compare_golden_snapshot(fixture_id, zig_results, golden, assertions)
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
        root_path = root / fixture.get("path", "")
        assertions = fixture.get("assertions", {})

        results = {
            "zig": {},
            "c": {},
            "request_count": 0,
            "comparison": {},
            "errors": [],
        }  # type: Dict[str, Any]

        for impl in ("zig", "c"):
            bin_path = str(zig_bin if impl == "zig" else c_bin)
            requests, tool_ctx = build_requests(root, fixture, impl)
            results["request_count"] = len(requests)
            try:
                tool_results = call_mcp_sequence(bin_path, str(root_path), requests, impl)
                tool_results["tool_ctx"] = tool_ctx
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
                        if z_missing or c_missing:
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "search_nodes"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(cases)}

            if scope == "query_graph":
                z_entries = get_entries("zig", scope)
                c_entries = get_entries("c", scope)
                if not z_entries or not c_entries:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_entries), "c": bool(c_entries)}
                else:
                    z_q = [canonical_query(entry["payload"]) for entry in z_entries]
                    c_q = [canonical_query(entry["payload"]) for entry in c_entries]
                    if z_q != c_q:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "query_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_q, "c": c_q}
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
                    for index, assertion in enumerate(assertions.get("get_architecture", [])):
                        expected = assertion.get("expect", {})
                        z_arch = canonical_architecture(z_entries[index]["payload"])
                        c_arch = canonical_architecture(c_entries[index]["payload"])
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
                        expected_rows = assertion.get("expect", {}).get("required_results", [])
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
                        if not same_shape:
                            has_mismatch = True
                        cases.append({"required_results": case_rows, "zig": z_rows, "c": c_rows})
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
                    for index, assertion in enumerate(assertions.get("get_graph_schema", [])):
                        expected = assertion.get("expect", {})
                        z_schema = canonical_graph_schema(z_entries[index]["payload"])
                        c_schema = canonical_graph_schema(c_entries[index]["payload"])
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
                    for index, assertion in enumerate(assertions.get("get_code_snippet", [])):
                        z_snippet = canonical_code_snippet(z_entries[index]["payload"])
                        c_snippet = canonical_code_snippet(c_entries[index]["payload"])
                        case = {
                            "zig": z_snippet,
                            "c": c_snippet,
                        }
                        if z_snippet != c_snippet:
                            has_mismatch = True
                        cases.append(case)
                    if has_mismatch:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "code_snippet_payload"}
                        )
                        comparisons[scope] = {"status": "mismatch", "cases": cases}
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
                        if z_status != c_status:
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
                        if z_result != c_result:
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
                z_fp = results["zig"].get("fixture_project", {})
                c_fp = results["c"].get("fixture_project", {})
                if not z_fp or not c_fp:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_fp), "c": bool(c_fp)}
                else:
                    z_project = {k: z_fp[k] for k in ("root_path",)}
                    c_project = {k: c_fp[k] for k in ("root_path",)}
                    if z_project != c_project:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "list_projects"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_project, "c": c_project}
                    else:
                        comparisons[scope] = {"status": "match"}

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
