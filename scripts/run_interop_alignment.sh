#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST_PATH="${1:-$ROOT_DIR/testdata/interop/manifest.json}"
C_BIN_DEFAULT="$ROOT_DIR/../codebase-memory-mcp/build/c/codebase-memory-mcp"
ZIG_BIN_DEFAULT="$ROOT_DIR/zig-out/bin/cbm"
C_BIN="${CODEBASE_MEMORY_C_BIN:-$C_BIN_DEFAULT}"
ZIG_BIN="${CODEBASE_MEMORY_ZIG_BIN:-$ZIG_BIN_DEFAULT}"
REPORT_DIR="${2:-$ROOT_DIR/.interop_reports}"

if [ ! -d "$REPORT_DIR" ]; then
  mkdir -p "$REPORT_DIR"
fi

python3 - "$MANIFEST_PATH" "$ROOT_DIR" "$C_BIN" "$ZIG_BIN" "$REPORT_DIR" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SHARED_TOOL_NAMES = [
    "delete_project",
    "detect_changes",
    "get_architecture",
    "get_code_snippet",
    "get_graph_schema",
    "index_repository",
    "index_status",
    "list_projects",
    "query_graph",
    "search_code",
    "search_graph",
    "trace_call_path",
]


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


def extract_tool_payload(raw: str, allow_content_wrapper: bool = True) -> tuple[dict[str, Any] | list[Any] | str, str | None]:
    envelope = parse_rpc_envelope(raw)
    if "error" in envelope:
        return {"__error__": envelope.get("error")}, "error"

    result = envelope.get("result")
    status = None
    if isinstance(result, dict) and "content" in result and allow_content_wrapper:
        content = result.get("content") or []
        if isinstance(content, list) and content:
            text = content[0].get("text", "")
            try:
                result = json.loads(text)
            except Exception:
                result = text
            status = "ok"
        else:
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
        return {"node_labels": [], "edge_types": [], "languages": [], "entry_points": []}

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
        "languages": collect_named(payload.get("languages"), "language"),
        "entry_points": collect_named(payload.get("entry_points"), "name"),
    }


def canonical_search_code(payload: Any) -> list[dict[str, str]]:
    if not isinstance(payload, dict):
        return []
    results = payload.get("results", [])
    if not isinstance(results, list):
        return []
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
    normalized.sort(key=lambda item: (item["name"], item["file_path"], item["label"]))
    return normalized


def canonical_detect_changes(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"changed_files": [], "changed_count": 0, "impacted_symbols": [], "blast_radius": []}

    changed_files = payload.get("changed_files", [])
    impacted_symbols = payload.get("impacted_symbols", [])
    blast_radius = payload.get("blast_radius", [])

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

    normalized_blast = []
    if isinstance(blast_radius, list):
        for item in blast_radius:
            if not isinstance(item, dict):
                continue
            normalized_blast.append(
                {
                    "name": str(item.get("name", "")),
                    "file_path": normalize_path_for_manifest(str(item.get("file_path", item.get("file", "")))),
                    "hop": str(item.get("hop", "")),
                }
            )
    normalized_blast.sort(key=lambda item: (item["name"], item["file_path"], item["hop"]))

    normalized_files = []
    if isinstance(changed_files, list):
        normalized_files = sorted(normalize_path_for_manifest(str(path)) for path in changed_files)

    return {
        "changed_files": normalized_files,
        "changed_count": int(payload.get("changed_count", len(normalized_files)) or 0),
        "impacted_symbols": normalized_impacted,
        "blast_radius": normalized_blast,
    }


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
) -> tuple[str | None, dict[str, Any], str]:
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
            for key in ("required_node_labels", "required_edge_types", "required_languages", "required_entry_points"):
                expected_values = set(expected.get(key, []))
                actual_key = {
                    "required_node_labels": "node_labels",
                    "required_edge_types": "edge_types",
                    "required_languages": "languages",
                    "required_entry_points": "entry_points",
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
                for result in results:
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
            if expected.get("require_empty_blast_radius") and changes["blast_radius"]:
                failures.append("detect_changes blast_radius not empty")
            continue

        if tool_name == "list_projects":
            entries = canonical_list_projects(tool_payload or {})
            if len(entries) == 0:
                failures.append("list_projects empty")
            continue

    return failures


def main() -> None:
    manifest_path = Path(sys.argv[1])
    root = Path(sys.argv[2]).resolve()
    c_bin = Path(sys.argv[3])
    zig_bin = Path(sys.argv[4])
    report_dir = Path(sys.argv[5]).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(manifest_path.read_text())
    report: dict[str, Any] = {
        "manifest": str(manifest_path),
        "fixtures": {},
        "mismatches": [],
    }

    for fixture in manifest.get("fixtures", []):
        fixture_id = fixture.get("id", fixture.get("project", "unknown"))
        root_path = root / fixture.get("path", "")
        assertions = fixture.get("assertions", {})

        results: dict[str, Any] = {
            "zig": {},
            "c": {},
            "request_count": 0,
            "comparison": {},
            "errors": [],
        }

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

            for scope_tool in ("search_graph", "query_graph", "trace_call_path", "get_architecture", "search_code", "detect_changes"):
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
        def get_entries(impl_name: str, tool_name: str) -> list[dict[str, Any]]:
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
                            ("required_languages", "languages"),
                            ("required_entry_points", "entry_points"),
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
                        case_rows = []
                        for expected_row in expected_rows:
                            z_match = any(
                                row["name"] == expected_row.get("name", row["name"])
                                and row["file_path"] == expected_row.get("file_path", row["file_path"])
                                and row["label"] == expected_row.get("label", row["label"])
                                for row in z_rows
                            )
                            c_match = any(
                                row["name"] == expected_row.get("name", row["name"])
                                and row["file_path"] == expected_row.get("file_path", row["file_path"])
                                and row["label"] == expected_row.get("label", row["label"])
                                for row in c_rows
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
                        cases.append({"required_results": case_rows})
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

    out_md.write_text("\n".join(lines) + "\n")
    print(f"wrote report: {out_json}")
    print(f"wrote report: {out_md}")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
PY
