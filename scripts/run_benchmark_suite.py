#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


TIME_BIN = Path("/usr/bin/time")


def to_unix_path(path: str) -> str:
    return str(Path(path).as_posix())


def normalize_project_name_for_c(project_path: str) -> str:
    return to_unix_path(project_path).replace("/", "-").lstrip("-")


def project_name_for_zig(project_path: Path, repo: dict[str, Any]) -> str:
    return str(repo.get("project", project_path.name))


def extract_cli_payload(stdout: str) -> Any:
    text = stdout.strip()
    if not text:
        return {"__error__": "empty stdout"}
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return {"__error__": "invalid json", "__raw__": text}

    result = payload
    if isinstance(payload, dict) and "result" in payload:
        result = payload.get("result")

    if isinstance(result, dict) and "content" in result:
        content = result.get("content") or []
        if isinstance(content, list) and content:
            inner = content[0].get("text", "")
            try:
                return json.loads(inner)
            except Exception:
                return inner
    return result


def canonical_search_nodes(payload: Any) -> list[dict[str, str]]:
    if not isinstance(payload, dict):
        return []
    nodes = payload.get("nodes", payload.get("results", []))
    if not isinstance(nodes, list):
        return []
    normalized: list[dict[str, str]] = []
    for row in nodes:
        if not isinstance(row, dict):
            continue
        normalized.append(
            {
                "name": str(row.get("name", "")),
                "label": str(row.get("label", "")),
                "qualified_name": str(row.get("qualified_name", "")),
                "file_path": to_unix_path(str(row.get("file_path", row.get("file", "")))),
            }
        )
    normalized.sort(key=lambda item: (item["name"], item["file_path"], item["qualified_name"]))
    return normalized


def canonical_query(payload: Any) -> tuple[list[str], list[list[str]]]:
    if not isinstance(payload, dict):
        return [], []
    columns: list[str] = []
    for value in payload.get("columns", []):
        text = str(value)
        lowered = text.lower()
        if lowered == "count" or lowered.startswith("count("):
            columns.append("count")
        else:
            columns.append(text)
    rows: list[list[str]] = []
    for row in payload.get("rows", []):
        if isinstance(row, list):
            rows.append([str(cell) for cell in row])
    return columns, rows


def canonical_trace(payload: Any) -> list[tuple[str, str, str]]:
    if not isinstance(payload, dict):
        return []

    def canonical_symbol_identity(value: Any) -> str:
        text = str(value or "")
        for separator in (":", "."):
            if separator in text:
                text = text.rsplit(separator, 1)[-1]
        return text

    edges: list[tuple[str, str, str]] = []
    if isinstance(payload.get("edges"), list):
        for edge in payload["edges"]:
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
        return sorted(edges)

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
    return sorted(edges)


def parse_max_rss(stderr: str) -> int | None:
    for line in stderr.splitlines():
        stripped = line.strip()
        if stripped.endswith("maximum resident set size"):
            parts = stripped.split()
            if parts:
                try:
                    return int(parts[0])
                except ValueError:
                    return None
    return None


def create_runtime_env(temp_home: str) -> dict[str, str]:
    env = os.environ.copy()
    env["HOME"] = temp_home
    env["CBM_CACHE_DIR"] = str(Path(temp_home) / ".cache" / "codebase-memory-bench")
    return env


def run_command(cmd: list[str], env: dict[str, str], cwd: str, measure: bool) -> dict[str, Any]:
    wrapped_cmd = cmd
    if measure and TIME_BIN.exists():
        wrapped_cmd = [str(TIME_BIN), "-l", *cmd]
    start = time.perf_counter()
    proc = subprocess.run(
        wrapped_cmd,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return {
        "command": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "elapsed_ms": elapsed_ms,
        "max_rss": parse_max_rss(proc.stderr) if measure else None,
    }


def build_cli_args(tool: str, tool_args: dict[str, Any], repo_abs: Path, repo: dict[str, Any], impl: str) -> tuple[str, dict[str, Any]]:
    args = json.loads(json.dumps(tool_args))
    zig_project = project_name_for_zig(repo_abs, repo)
    c_project = normalize_project_name_for_c(str(repo_abs))

    if tool == "index_repository":
        return tool, ({"project_path": str(repo_abs)} if impl == "zig" else {"repo_path": str(repo_abs)})

    if tool == "search_graph":
        args["project"] = zig_project if impl == "zig" else c_project
        if impl == "zig":
            if "label" in args:
                args["label_pattern"] = args.pop("label")
        else:
            args.pop("label_pattern", None)
        return tool, args

    if tool == "query_graph":
        args["project"] = zig_project if impl == "zig" else c_project
        return tool, args

    if tool == "search_code":
        args["project"] = zig_project if impl == "zig" else c_project
        return tool, args

    if tool == "get_architecture":
        args["project"] = zig_project if impl == "zig" else c_project
        return tool, args

    if tool == "get_code_snippet":
        args["project"] = zig_project if impl == "zig" else c_project
        return tool, args

    if tool == "trace_call_path":
        args["project"] = zig_project if impl == "zig" else c_project
        if impl == "c":
            tool_name = "trace_path"
            if "function_name" not in args and "start_node_name_hint" in args:
                args["function_name"] = args.pop("start_node_name_hint")
            if args.get("direction") == "out":
                args["direction"] = "outbound"
            elif args.get("direction") == "in":
                args["direction"] = "inbound"
            return tool_name, args
        return tool, args

    return tool, args


def run_cli_tool(
    *,
    bin_path: str,
    repo_abs: Path,
    repo: dict[str, Any],
    impl: str,
    env: dict[str, str],
    tool: str,
    tool_args: dict[str, Any],
    measure: bool,
) -> dict[str, Any]:
    tool_name, args = build_cli_args(tool, tool_args, repo_abs, repo, impl)

    if impl == "zig" and tool == "trace_call_path" and "start_node_qn" not in args:
        hint = str(args.pop("start_node_name_hint", ""))
        if hint:
            resolved = resolve_start_node_qn(bin_path, repo_abs, repo, env, hint)
            if resolved is None:
                return {
                    "command": [],
                    "returncode": 1,
                    "stdout": "",
                    "stderr": f"unable to resolve start_node_qn for {hint}",
                    "elapsed_ms": 0.0,
                    "max_rss": None,
                    "payload": {"__error__": "unresolved start node"},
                }
            args["start_node_qn"] = resolved

    command = [bin_path, "cli", tool_name, json.dumps(args, separators=(",", ":"))]
    result = run_command(command, env=env, cwd=str(repo_abs.parent), measure=measure)
    result["payload"] = extract_cli_payload(result["stdout"])
    return result


def resolve_start_node_qn(bin_path: str, repo_abs: Path, repo: dict[str, Any], env: dict[str, str], hint: str) -> str | None:
    result = run_cli_tool(
        bin_path=bin_path,
        repo_abs=repo_abs,
        repo=repo,
        impl="zig",
        env=env,
        tool="search_graph",
        tool_args={"name_pattern": hint, "limit": 25},
        measure=False,
    )
    payload = result.get("payload")
    nodes = [node for node in canonical_search_nodes(payload) if node["name"] == hint]
    preferred_labels = {"Function", "Method", "Class", "Interface", "Trait", "Struct"}
    preferred = [node for node in nodes if node["label"] in preferred_labels]
    if len(preferred) == 1:
        return preferred[0]["qualified_name"]
    if len(nodes) == 1:
        return nodes[0]["qualified_name"]
    return None


def grade_search_graph(payload: Any, expect: dict[str, Any]) -> tuple[str, float, dict[str, Any]]:
    required = list(expect.get("required_names", []))
    if not required:
        return "N/A", 0.0, {"reason": "no required_names"}
    names = {node["name"] for node in canonical_search_nodes(payload)}
    found = sorted(name for name in required if name in names)
    missing = sorted(name for name in required if name not in names)
    if not missing:
        return "PASS", 1.0, {"found": found, "missing": missing}
    if found:
        return "PARTIAL", 0.5, {"found": found, "missing": missing}
    return "FAIL", 0.0, {"found": found, "missing": missing}


def grade_query_graph(payload: Any, expect: dict[str, Any]) -> tuple[str, float, dict[str, Any]]:
    columns, rows = canonical_query(payload)
    expected_columns = list(expect.get("columns", []))
    rows_min = int(expect.get("required_rows_min", 0))
    column_match = (not expected_columns) or columns == expected_columns
    row_match = len(rows) >= rows_min
    if column_match and row_match:
        return "PASS", 1.0, {"columns": columns, "row_count": len(rows)}
    if column_match or row_match:
        return "PARTIAL", 0.5, {"columns": columns, "row_count": len(rows)}
    return "FAIL", 0.0, {"columns": columns, "row_count": len(rows)}


def grade_trace_call_path(payload: Any, expect: dict[str, Any]) -> tuple[str, float, dict[str, Any]]:
    required_types = list(expect.get("required_edge_types", []))
    if not required_types:
        return "N/A", 0.0, {"reason": "no required_edge_types"}
    edges = canonical_trace(payload)
    actual_types = {edge[2] for edge in edges}
    found = sorted(edge_type for edge_type in required_types if edge_type in actual_types)
    missing = sorted(edge_type for edge_type in required_types if edge_type not in actual_types)
    if not missing:
        return "PASS", 1.0, {"edge_count": len(edges), "missing": missing}
    if found:
        return "PARTIAL", 0.5, {"edge_count": len(edges), "missing": missing}
    return "FAIL", 0.0, {"edge_count": len(edges), "missing": missing}


def grade_get_code_snippet(payload: Any, expect: dict[str, Any]) -> tuple[str, float, dict[str, Any]]:
    if not isinstance(payload, dict):
        return "FAIL", 0.0, {"reason": "missing payload"}
    source = str(payload.get("source", ""))
    if not source:
        return "FAIL", 0.0, {"reason": "empty source"}
    required = [str(item) for item in expect.get("required_substrings", [])]
    missing = [item for item in required if item not in source]
    if not missing:
        return "PASS", 1.0, {"missing": missing}
    if len(missing) < len(required):
        return "PARTIAL", 0.5, {"missing": missing}
    return "FAIL", 0.0, {"missing": missing}


def grade_scenario(tool: str, payload: Any, expect: dict[str, Any]) -> tuple[str, float, dict[str, Any]]:
    if isinstance(payload, dict) and payload.get("__error__"):
        return "FAIL", 0.0, {"reason": payload.get("__error__")}
    if tool == "search_graph":
        return grade_search_graph(payload, expect)
    if tool == "query_graph":
        return grade_query_graph(payload, expect)
    if tool == "trace_call_path":
        return grade_trace_call_path(payload, expect)
    if tool == "get_code_snippet":
        return grade_get_code_snippet(payload, expect)
    return "N/A", 0.0, {"reason": f"unsupported grading tool {tool}"}


def summarize_measurements(values: list[dict[str, Any]]) -> dict[str, Any]:
    if not values:
        return {"count": 0}
    elapsed = [entry["elapsed_ms"] for entry in values]
    rss_values = [entry["max_rss"] for entry in values if entry.get("max_rss") is not None]
    summary = {
        "count": len(values),
        "median_ms": round(statistics.median(elapsed), 3),
        "min_ms": round(min(elapsed), 3),
        "max_ms": round(max(elapsed), 3),
    }
    if rss_values:
        summary["median_max_rss"] = int(statistics.median(rss_values))
        summary["max_max_rss"] = int(max(rss_values))
    return summary


def run_accuracy_suite(bin_path: str, repo_abs: Path, repo: dict[str, Any], impl: str) -> dict[str, Any]:
    scenarios = repo.get("accuracy_scenarios", [])
    if not scenarios:
        return {"score": {"earned": 0.0, "possible": 0.0}, "scenarios": []}

    with tempfile.TemporaryDirectory(prefix=f"cbm-bench-accuracy-{impl}-") as temp_home:
        env = create_runtime_env(temp_home)
        index_result = run_cli_tool(
            bin_path=bin_path,
            repo_abs=repo_abs,
            repo=repo,
            impl=impl,
            env=env,
            tool="index_repository",
            tool_args={},
            measure=False,
        )
        scenario_results: list[dict[str, Any]] = []
        earned = 0.0
        possible = 0.0
        for scenario in scenarios:
            tool = str(scenario["tool"])
            result = run_cli_tool(
                bin_path=bin_path,
                repo_abs=repo_abs,
                repo=repo,
                impl=impl,
                env=env,
                tool=tool,
                tool_args=scenario.get("args", {}),
                measure=False,
            )
            grade, score, details = grade_scenario(tool, result.get("payload"), scenario.get("expect", {}))
            if grade != "N/A":
                possible += 1.0
                earned += score
            scenario_results.append(
                {
                    "id": scenario.get("id", tool),
                    "tool": tool,
                    "grade": grade,
                    "score": score,
                    "details": details,
                    "returncode": result["returncode"],
                    "payload": result.get("payload"),
                }
            )
        return {
            "index_returncode": index_result["returncode"],
            "score": {"earned": earned, "possible": possible},
            "scenarios": scenario_results,
        }


def run_index_benchmark(bin_path: str, repo_abs: Path, repo: dict[str, Any], impl: str, measured_runs: int) -> dict[str, Any]:
    runs: list[dict[str, Any]] = []
    for _ in range(measured_runs):
        with tempfile.TemporaryDirectory(prefix=f"cbm-bench-index-{impl}-") as temp_home:
            env = create_runtime_env(temp_home)
            result = run_cli_tool(
                bin_path=bin_path,
                repo_abs=repo_abs,
                repo=repo,
                impl=impl,
                env=env,
                tool="index_repository",
                tool_args={},
                measure=True,
            )
            runs.append(
                {
                    "elapsed_ms": round(result["elapsed_ms"], 3),
                    "max_rss": result.get("max_rss"),
                    "returncode": result["returncode"],
                }
            )
    return {"runs": runs, "summary": summarize_measurements(runs)}


def run_query_benchmarks(
    bin_path: str,
    repo_abs: Path,
    repo: dict[str, Any],
    impl: str,
    warmup_runs: int,
    measured_runs: int,
) -> dict[str, Any]:
    scenarios = repo.get("performance_scenarios", [])
    if not scenarios:
        return {}

    grouped: dict[str, list[dict[str, Any]]] = {str(scenario["id"]): [] for scenario in scenarios}

    for run_index in range(warmup_runs + measured_runs):
        measure = run_index >= warmup_runs
        with tempfile.TemporaryDirectory(prefix=f"cbm-bench-query-{impl}-") as temp_home:
            env = create_runtime_env(temp_home)
            index_result = run_cli_tool(
                bin_path=bin_path,
                repo_abs=repo_abs,
                repo=repo,
                impl=impl,
                env=env,
                tool="index_repository",
                tool_args={},
                measure=False,
            )
            if index_result["returncode"] != 0:
                if measure:
                    for scenario in scenarios:
                        grouped[str(scenario["id"])].append(
                            {
                                "elapsed_ms": 0.0,
                                "max_rss": None,
                                "returncode": index_result["returncode"],
                                "error": "index setup failed",
                            }
                        )
                continue

            for scenario in scenarios:
                result = run_cli_tool(
                    bin_path=bin_path,
                    repo_abs=repo_abs,
                    repo=repo,
                    impl=impl,
                    env=env,
                    tool=str(scenario["tool"]),
                    tool_args=scenario.get("args", {}),
                    measure=measure,
                )
                if measure:
                    grouped[str(scenario["id"])].append(
                        {
                            "elapsed_ms": round(result["elapsed_ms"], 3),
                            "max_rss": result.get("max_rss"),
                            "returncode": result["returncode"],
                        }
                    )

    return {
        scenario_id: {
            "tool": next(str(spec["tool"]) for spec in scenarios if str(spec["id"]) == scenario_id),
            "runs": runs,
            "summary": summarize_measurements(runs),
        }
        for scenario_id, runs in grouped.items()
    }


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def build_markdown_report(report: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append("# Benchmark Suite Report")
    lines.append("")
    lines.append(f"- Manifest: `{report['manifest']}`")
    lines.append(f"- Generated at: `{report['generated_at']}`")
    lines.append(f"- Host: `{report['host']}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Repo | Zig Accuracy | C Accuracy | Delta | Zig Index Median (ms) | C Index Median (ms) | Faster |")
    lines.append("|------|--------------:|-----------:|------:|----------------------:|--------------------:|--------|")
    for repo in report["repos"]:
        zig_score = repo["zig"]["accuracy"]["score"]
        c_score = repo["c"]["accuracy"]["score"]
        zig_possible = zig_score["possible"] or 0.0
        c_possible = c_score["possible"] or 0.0
        zig_pct = 0.0 if zig_possible == 0 else (zig_score["earned"] / zig_possible) * 100.0
        c_pct = 0.0 if c_possible == 0 else (c_score["earned"] / c_possible) * 100.0
        delta = zig_pct - c_pct
        zig_index = repo["zig"]["performance"]["index"]["summary"].get("median_ms", "-")
        c_index = repo["c"]["performance"]["index"]["summary"].get("median_ms", "-")
        faster = repo["comparison"].get("index_faster", "n/a")
        lines.append(
            f"| {repo['id']} | {zig_pct:.1f}% | {c_pct:.1f}% | {delta:+.1f} | {zig_index} | {c_index} | {faster} |"
        )

    for repo in report["repos"]:
        lines.append("")
        lines.append(f"## {repo['id']}")
        lines.append("")
        notes = repo.get("notes", [])
        if notes:
            for note in notes:
                lines.append(f"- {note}")
            lines.append("")

        for impl in ("zig", "c"):
            accuracy = repo[impl]["accuracy"]
            score = accuracy["score"]
            possible = score["possible"] or 0.0
            pct = 0.0 if possible == 0 else (score["earned"] / possible) * 100.0
            lines.append(f"### {impl.upper()}")
            lines.append("")
            lines.append(f"- Accuracy: {score['earned']:.1f}/{possible:.1f} ({pct:.1f}%)")
            lines.append(f"- Cold index median: {repo[impl]['performance']['index']['summary'].get('median_ms', 'n/a')} ms")
            lines.append("")
            if accuracy["scenarios"]:
                lines.append("| Scenario | Tool | Grade |")
                lines.append("|----------|------|-------|")
                for scenario in accuracy["scenarios"]:
                    lines.append(f"| {scenario['id']} | {scenario['tool']} | {scenario['grade']} |")
                lines.append("")
            query_perf = repo[impl]["performance"].get("queries", {})
            if query_perf:
                lines.append("| Query Scenario | Tool | Median (ms) | Median RSS |")
                lines.append("|----------------|------|------------:|-----------:|")
                for scenario_id, entry in query_perf.items():
                    lines.append(
                        f"| {scenario_id} | {entry['tool']} | {entry['summary'].get('median_ms', 'n/a')} | {entry['summary'].get('median_max_rss', 'n/a')} |"
                    )
                lines.append("")

    return "\n".join(lines) + "\n"


def compare_repo_results(repo_result: dict[str, Any]) -> dict[str, Any]:
    zig_index = repo_result["zig"]["performance"]["index"]["summary"].get("median_ms")
    c_index = repo_result["c"]["performance"]["index"]["summary"].get("median_ms")
    faster = "tie"
    if isinstance(zig_index, (int, float)) and isinstance(c_index, (int, float)):
        if zig_index < c_index:
            faster = "zig"
        elif c_index < zig_index:
            faster = "c"
    return {"index_faster": faster}


def run_repo_suite(repo: dict[str, Any], zig_bin: str, c_bin: str, root: Path) -> dict[str, Any]:
    repo_abs = (root / repo["path"]).resolve()
    warmup_runs = int(repo.get("warmup_runs", 1))
    measured_runs = int(repo.get("measured_runs", 2))

    result = {
        "id": repo["id"],
        "path": str(repo_abs),
        "notes": list(repo.get("notes", [])),
        "zig": {},
        "c": {},
    }

    for impl, bin_path in (("zig", zig_bin), ("c", c_bin)):
        accuracy = run_accuracy_suite(bin_path, repo_abs, repo, impl)
        performance = {
            "index": run_index_benchmark(bin_path, repo_abs, repo, impl, measured_runs),
            "queries": run_query_benchmarks(bin_path, repo_abs, repo, impl, warmup_runs, measured_runs),
        }
        result[impl] = {
            "accuracy": accuracy,
            "performance": performance,
        }

    result["comparison"] = compare_repo_results(result)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--zig-bin", required=True)
    parser.add_argument("--c-bin", required=True)
    parser.add_argument("--report-dir", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest).resolve()
    root = Path(args.root).resolve()
    report_dir = Path(args.report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(manifest_path)
    report = {
        "manifest": str(manifest_path),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": os.uname().nodename,
        "repos": [],
    }

    for repo in manifest.get("repos", []):
        report["repos"].append(run_repo_suite(repo, args.zig_bin, args.c_bin, root))

    json_path = report_dir / "benchmark_report.json"
    md_path = report_dir / "benchmark_report.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n")
    md_path.write_text(build_markdown_report(report))

    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
