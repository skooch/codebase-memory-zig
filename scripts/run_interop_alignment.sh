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


def canonical_search_nodes(payload: Any) -> list[dict[str, str]]:
    if not isinstance(payload, dict):
        return []
    nodes = payload.get("nodes", [])
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
    normalized.sort(key=lambda item: (item["label"], item["name"], item["qualified_name"], item["file_path"]))
    return normalized


def canonical_query(payload: Any) -> tuple[tuple[str, ...], list[tuple[str, ...]]]:
    if not isinstance(payload, dict):
        return tuple(), []
    columns = tuple(str(col) for col in payload.get("columns", []))
    rows = []
    for row in payload.get("rows", []):
        if not isinstance(row, list):
            continue
        rows.append(tuple(str(cell) for cell in row))
    rows.sort()
    return columns, rows


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
            edges.append(
                (
                    str(edge.get("source", "")),
                    str(edge.get("target", "")),
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
            target = callee.get("name", "")
        else:
            target = callee
        edges.append((function_name, str(target), "CALLS"))
    for caller in payload.get("callers", []) or []:
        if isinstance(caller, dict):
            source = caller.get("name", "")
        else:
            source = caller
        edges.append((str(source), function_name, "CALLS"))
    edges.sort()
    return edges


def canonical_list_projects(payload: Any) -> list[dict[str, Any]]:
    projects = payload.get("projects", []) if isinstance(payload, dict) else []
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


def call_mcp_batch(bin_path: str, project_path: str, scenario: list[dict[str, Any]], is_c: bool) -> dict[str, Any]:
    env = os.environ.copy()
    if is_c:
        env["HOME"] = tempfile.mkdtemp(prefix="cbm-interop-")
    process = subprocess.Popen(
        [bin_path],
        cwd=str(Path(project_path).parent),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        input_lines = "\n".join(json.dumps(req) for req in scenario) + "\n"
        stdout, stderr = process.communicate(input=input_lines, timeout=60)
    except subprocess.TimeoutExpired:
        process.kill()
        raise

    responses = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            responses.append(json.loads(line))
        except Exception:
            continue

    tool_results: dict[str, Any] = {"tool": {}}
    request_methods = [entry for entry in scenario if entry.get("method") == "tools/call"]
    for idx, response in enumerate(responses):
        if idx >= len(request_methods):
            continue
        tool_name = request_methods[idx].get("params", {}).get("name")
        payload, status = extract_tool_payload(json.dumps(response))
        tool_results["tool"][tool_name] = {
            "status": status,
            "payload": payload,
            "raw": response,
            "id": response.get("id"),
        }
    tool_results["stderr"] = stderr.splitlines() if stderr else []
    tool_results["stdout"] = stdout.splitlines() if stdout else []
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
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {},
        },
        {
            "jsonrpc": "2.0",
            "id": 2,
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
    ]

    tool_id = 3
    assertions = fixture.get("assertions", {})
    for assertion in assertions.get("search_graph", []):
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            args = {k: v for k, v in args.items() if k != "label"}
            if "project" not in args:
                args["project"] = project_name
            if "label" in assertion.get("args", {}):
                args["label_pattern"] = assertion["args"]["label"]
        else:
            args = {k: v for k, v in args.items() if k != "label_pattern"}
            if "project" not in args:
                args["project"] = c_project_name
            if "label" in assertion.get("args", {}):
                args["label"] = assertion["args"]["label"]
        requests.append(
            {
                "jsonrpc": "2.0",
                "id": tool_id,
                "method": "tools/call",
                "params": {
                    "name": "search_graph",
                    "arguments": args,
                },
            }
        )
        tool_id += 1

    for assertion in assertions.get("query_graph", []):
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            if "project" not in args:
                args["project"] = project_name
        else:
            if "project" not in args:
                args["project"] = c_project_name
        requests.append(
            {
                "jsonrpc": "2.0",
                "id": tool_id,
                "method": "tools/call",
                "params": {
                    "name": "query_graph",
                    "arguments": args,
                },
            }
        )
        tool_id += 1

    for assertion in assertions.get("trace_call_path", []):
        tool_name = "trace_path" if impl == "c" else "trace_call_path"
        args = dict(assertion.get("args", {}))
        if impl == "zig":
            if "project" not in args:
                args["project"] = project_name
            if "start_node_qn" not in args:
                hint = args.pop("start_node_name_hint", "")
                if hint:
                    args["start_node_qn"] = hint
        else:
            if "project" not in args:
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
                "jsonrpc": "2.0",
                "id": tool_id,
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": args,
                },
            }
        )
        tool_id += 1

    requests.append(
        {
            "jsonrpc": "2.0",
            "id": tool_id,
            "method": "tools/call",
            "params": {
                "name": "list_projects",
                "arguments": {},
            },
        }
    )

    return requests, tool_ctx


def check_assertions(tool_name: str, tool_payload: Any, assertions: list[dict[str, Any]]) -> list[str]:
    failures = []
    for assertion in assertions:
        expected = assertion.get("expect", {})
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
                tool_results = call_mcp_batch(bin_path, str(root_path), requests, impl == "c")
                tool_results["tool_ctx"] = tool_ctx
                results[impl] = tool_results
            except Exception as err:
                results["errors"].append(f"{impl}: {err}")
                continue

            impl_payloads = results[impl]["tool"]

            # Normalize and validate index output if requested.
            index_payload = impl_payloads.get("index_repository", {}).get("payload", {})
            index_assertions = assertions.get("index_repository", {})
            if index_assertions:
                failures = check_assertions("index_repository", index_payload, [index_assertions])
                if failures:
                    results[impl].setdefault("assertion_failures", []).append(
                        {"tool": "index_repository", "failures": failures}
                    )

            for scope_tool in ("search_graph", "query_graph", "trace_call_path"):
                assertion_key = scope_tool
                for assertion in assertions.get(assertion_key, []):
                    payload = impl_payloads.get(
                        scope_tool,
                        {"payload": {"__missing__": True}},
                    ).get("payload")
                    failures = check_assertions(scope_tool, payload, [assertion])
                    if failures:
                        results[impl].setdefault("assertion_failures", []).append(
                            {"tool": scope_tool, "assert": assertion, "failures": failures}
                        )

            # list_projects is global and used as fixture-scoped indexing signal.
            list_payload = impl_payloads.get("list_projects", {}).get("payload", {})
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
        def get_payload(impl_name: str, tool_name: str) -> Any:
            tool = results[impl_name].get("tool", {}).get(tool_name, {})
            return tool.get("payload") if isinstance(tool, dict) else None

        comparisons = {}
        for scope in ("search_graph", "query_graph", "trace_call_path", "list_projects", "index_repository"):
            if scope == "search_graph":
                z = get_payload("zig", scope)
                c = get_payload("c", scope)
                if z is None or c is None:
                    comparisons[scope] = {"status": "missing", "zig": z is not None, "c": c is not None}
                else:
                    z_norm = canonical_search_nodes(z)
                    c_norm = canonical_search_nodes(c)
                    if z_norm != c_norm:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "search_nodes"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_norm, "c": c_norm}
                    else:
                        comparisons[scope] = {"status": "match", "count": len(z_norm)}

            if scope == "query_graph":
                z = get_payload("zig", scope)
                c = get_payload("c", scope)
                if z is None or c is None:
                    comparisons[scope] = {"status": "missing", "zig": z is not None, "c": c is not None}
                else:
                    z_q = canonical_query(z)
                    c_q = canonical_query(c)
                    if z_q != c_q:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "query_result"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_q, "c": c_q}
                    else:
                        comparisons[scope] = {"status": "match"}

            if scope == "trace_call_path":
                z = get_payload("zig", scope)
                c = get_payload("c", scope)
                if z is None or c is None:
                    comparisons[scope] = {"status": "missing", "zig": z is not None, "c": c is not None}
                else:
                    z_t = canonical_trace(z)
                    c_t = canonical_trace(c)
                    if z_t != c_t:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "trace_edges"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_t, "c": c_t}
                    else:
                        comparisons[scope] = {"status": "match"}

            if scope == "list_projects":
                z_fp = results["zig"].get("fixture_project", {})
                c_fp = results["c"].get("fixture_project", {})
                if not z_fp or not c_fp:
                    comparisons[scope] = {"status": "missing", "zig": bool(z_fp), "c": bool(c_fp)}
                else:
                    z_project = {k: z_fp[k] for k in ("root_path", "nodes", "edges")}
                    c_project = {k: c_fp[k] for k in ("root_path", "nodes", "edges")}
                    if z_project != c_project:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "list_projects"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": z_project, "c": c_project}
                    else:
                        comparisons[scope] = {"status": "match"}

            if scope == "index_repository":
                z = results["zig"].get("tool", {}).get("index_repository", {}).get("payload")
                c = results["c"].get("tool", {}).get("index_repository", {}).get("payload")
                if z is None or c is None:
                    comparisons[scope] = {"status": "missing", "zig": z is not None, "c": c is not None}
                else:
                    z_nodes = int(z.get("nodes", 0))
                    c_nodes = int(c.get("nodes", 0))
                    z_edges = int(z.get("edges", 0))
                    c_edges = int(c.get("edges", 0))
                    if z_nodes != c_nodes or z_edges != c_edges:
                        report["mismatches"].append(
                            {"fixture": fixture_id, "tool": scope, "category": "index_summary"}
                        )
                        comparisons[scope] = {"status": "mismatch", "zig": {"nodes": z_nodes, "edges": z_edges}, "c": {"nodes": c_nodes, "edges": c_edges}}
                    else:
                        comparisons[scope] = {"status": "match", "nodes": z_nodes, "edges": z_edges}

        results["comparison"] = comparisons
        report["fixtures"][fixture_id] = results

    out_json = report_dir / "interop_alignment_report.json"
    out_md = report_dir / "interop_alignment_report.md"

    out_json.write_text(json.dumps(report, indent=2))

    total_fixtures = len(report["fixtures"])
    total_matches = sum(1 for r in report["fixtures"].values() for cmp in r.get("comparison", {}).values() if isinstance(cmp, dict) and cmp.get("status") == "match")
    total_comparisons = total_fixtures * 5
    mismatch_count = len(report["mismatches"])

    lines = [
        "# Interop Alignment Baseline",
        "",
        f"- Fixtures: {total_fixtures}",
        f"- Comparisons: {total_comparisons}",
        f"- Matches: {total_matches}",
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
