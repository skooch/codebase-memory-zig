#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any

from run_benchmark_suite import create_runtime_env, run_cli_tool, summarize_measurements


AGENTS = (
    ("original", "c"),
    ("hybrid", "zig"),
)

KEY_ALIASES = {
    "total": {"total", "total_results"},
    "file_path": {"file_path", "file"},
}


def iter_field_values(payload: Any, keys: set[str]) -> list[str]:
    values: list[str] = []

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in keys and not isinstance(value, (dict, list)):
                    values.append(str(value))
                visit(value)
        elif isinstance(node, list):
            for item in node:
                visit(item)

    visit(payload)
    return values


def grade_payload(payload: Any, expect: dict[str, Any]) -> dict[str, Any]:
    if isinstance(payload, dict) and payload.get("__error__"):
        return {"status": "FAIL", "score": 0.0, "details": {"reason": payload.get("__error__")}}

    checks = 0
    passed = 0
    details: dict[str, Any] = {}

    required_substrings = [str(item) for item in expect.get("required_substrings", [])]
    if required_substrings:
        checks += len(required_substrings)
        haystack = payload if isinstance(payload, str) else json.dumps(payload, sort_keys=True)
        missing = [item for item in required_substrings if item not in haystack]
        passed += len(required_substrings) - len(missing)
        details["missing_substrings"] = missing

    required_names = [str(item) for item in expect.get("required_names", [])]
    if required_names:
        checks += len(required_names)
        names = set(iter_field_values(payload, {"name", "node"}))
        missing = [item for item in required_names if item not in names]
        passed += len(required_names) - len(missing)
        details["missing_names"] = missing

    required_files = [str(item) for item in expect.get("required_files", [])]
    if required_files:
        checks += len(required_files)
        files = set(iter_field_values(payload, {"file", "file_path"}))
        missing = [item for item in required_files if not any(path == item or path.endswith(item) for path in files)]
        passed += len(required_files) - len(missing)
        details["missing_files"] = missing

    required_keys = [str(item) for item in expect.get("required_keys", [])]
    if required_keys:
        checks += len(required_keys)
        payload_keys = set(payload.keys()) if isinstance(payload, dict) else set()
        missing = [
            item for item in required_keys if not (KEY_ALIASES.get(item, {item}) & payload_keys)
        ]
        passed += len(required_keys) - len(missing)
        details["missing_keys"] = missing

    if checks == 0:
        return {"status": "N/A", "score": 0.0, "details": {"reason": "no expectations"}}

    score = passed / checks
    if score == 1.0:
        status = "PASS"
    elif score > 0.0:
        status = "PARTIAL"
    else:
        status = "FAIL"
    return {"status": status, "score": round(score, 3), "details": details}


def choose_winner(original: dict[str, Any], hybrid: dict[str, Any]) -> str:
    original_grade = original["grade"]["score"]
    hybrid_grade = hybrid["grade"]["score"]
    if hybrid_grade > original_grade:
        return "hybrid"
    if original_grade > hybrid_grade:
        return "original"

    original_ms = original["summary"].get("median_ms")
    hybrid_ms = hybrid["summary"].get("median_ms")
    if isinstance(original_ms, (int, float)) and isinstance(hybrid_ms, (int, float)):
        if hybrid_ms < original_ms:
            return "hybrid"
        if original_ms < hybrid_ms:
            return "original"
    return "tie"


def run_agent(
    *,
    bin_path: str,
    repo_abs: Path,
    repo: dict[str, Any],
    impl: str,
    env: dict[str, str],
    task: dict[str, Any],
    warmup_runs: int,
    measured_runs: int,
) -> dict[str, Any]:
    task_tool = str(task["tool"])
    task_args = dict(task.get("args", {}))

    for _ in range(max(0, warmup_runs)):
        run_cli_tool(
            bin_path=bin_path,
            repo_abs=repo_abs,
            repo=repo,
            impl=impl,
            env=env,
            tool=task_tool,
            tool_args=task_args,
            measure=False,
        )

    measurements: list[dict[str, Any]] = []
    for _ in range(max(1, measured_runs)):
        measurements.append(
            run_cli_tool(
                bin_path=bin_path,
                repo_abs=repo_abs,
                repo=repo,
                impl=impl,
                env=env,
                tool=task_tool,
                tool_args=task_args,
                measure=True,
            )
        )

    payload = measurements[-1].get("payload")
    return {
        "tool": task_tool,
        "args": task_args,
        "payload": payload,
        "grade": grade_payload(payload, dict(task.get("expect", {}))),
        "summary": summarize_measurements(measurements),
        "measurements": measurements,
    }


def run_repo(
    *,
    repo: dict[str, Any],
    root_dir: Path,
    zig_bin: str,
    c_bin: str,
) -> dict[str, Any]:
    repo_abs = (root_dir / str(repo["path"])).resolve()
    warmup_runs = int(repo.get("warmup_runs", 0))
    measured_runs = int(repo.get("measured_runs", 1))

    with tempfile.TemporaryDirectory(prefix=f"cbm-agent-{repo['id']}-original-") as original_home, tempfile.TemporaryDirectory(
        prefix=f"cbm-agent-{repo['id']}-hybrid-"
    ) as hybrid_home:
        envs = {
            "original": create_runtime_env(original_home),
            "hybrid": create_runtime_env(hybrid_home),
        }
        index_results: dict[str, Any] = {}
        for label, impl in AGENTS:
            bin_path = c_bin if impl == "c" else zig_bin
            index_results[label] = run_cli_tool(
                bin_path=bin_path,
                repo_abs=repo_abs,
                repo=repo,
                impl=impl,
                env=envs[label],
                tool="index_repository",
                tool_args={},
                measure=True,
            )

        tasks: list[dict[str, Any]] = []
        for task in repo.get("tasks", []):
            original = run_agent(
                bin_path=c_bin,
                repo_abs=repo_abs,
                repo=repo,
                impl="c",
                env=envs["original"],
                task=task,
                warmup_runs=warmup_runs,
                measured_runs=measured_runs,
            )
            hybrid = run_agent(
                bin_path=zig_bin,
                repo_abs=repo_abs,
                repo=repo,
                impl="zig",
                env=envs["hybrid"],
                task=task,
                warmup_runs=warmup_runs,
                measured_runs=measured_runs,
            )
            tasks.append(
                {
                    "id": task["id"],
                    "prompt": task.get("prompt", ""),
                    "tool": task["tool"],
                    "expect": task.get("expect", {}),
                    "original": original,
                    "hybrid": hybrid,
                    "winner": choose_winner(original, hybrid),
                }
            )

        return {
            "id": repo["id"],
            "path": str(repo_abs),
            "notes": list(repo.get("notes", [])),
            "index": {
                "original": index_results["original"],
                "hybrid": index_results["hybrid"],
            },
            "tasks": tasks,
        }


def write_markdown(report: dict[str, Any], out_path: Path) -> None:
    overall = report["summary"]
    lines = [
        "# Agent Comparison Report",
        "",
        f"- Manifest: `{report['manifest']}`",
        f"- Generated at: `{report['generated_at']}`",
        f"- Host: `{report['host']}`",
        "",
        "## Summary",
        "",
        f"- Hybrid wins: `{overall['hybrid_wins']}`",
        f"- Original wins: `{overall['original_wins']}`",
        f"- Ties: `{overall['ties']}`",
        "",
        "| Repo | Task | Tool | Original Grade | Hybrid Grade | Original Median (ms) | Hybrid Median (ms) | Winner |",
        "|------|------|------|----------------|--------------|---------------------:|-------------------:|--------|",
    ]

    for repo in report["repos"]:
        for task in repo["tasks"]:
            lines.append(
                "| {repo} | {task_id} | {tool} | {orig_grade} | {hybrid_grade} | {orig_ms} | {hybrid_ms} | {winner} |".format(
                    repo=repo["id"],
                    task_id=task["id"],
                    tool=task["tool"],
                    orig_grade=task["original"]["grade"]["status"],
                    hybrid_grade=task["hybrid"]["grade"]["status"],
                    orig_ms=task["original"]["summary"].get("median_ms", "n/a"),
                    hybrid_ms=task["hybrid"]["summary"].get("median_ms", "n/a"),
                    winner=task["winner"],
                )
            )

    for repo in report["repos"]:
        lines.extend(["", f"## {repo['id']}", ""])
        notes = repo.get("notes", [])
        if notes:
            for note in notes:
                lines.append(f"- {note}")
            lines.append("")
        lines.append(
            "- Index median (original vs hybrid): `{orig}` ms vs `{hybrid}` ms".format(
                orig=repo["index"]["original"]["elapsed_ms"],
                hybrid=repo["index"]["hybrid"]["elapsed_ms"],
            )
        )
        lines.extend(
            [
                "",
                "| Task | Tool | Original | Hybrid | Winner |",
                "|------|------|----------|--------|--------|",
            ]
        )
        for task in repo["tasks"]:
            lines.append(
                "| {task_id} | {tool} | {orig} ({orig_ms} ms) | {hybrid} ({hybrid_ms} ms) | {winner} |".format(
                    task_id=task["id"],
                    tool=task["tool"],
                    orig=task["original"]["grade"]["status"],
                    hybrid=task["hybrid"]["grade"]["status"],
                    orig_ms=task["original"]["summary"].get("median_ms", "n/a"),
                    hybrid_ms=task["hybrid"]["summary"].get("median_ms", "n/a"),
                    winner=task["winner"],
                )
            )
            if task.get("prompt"):
                lines.append("")
                lines.append(f"Prompt: `{task['prompt']}`")

    out_path.write_text("\n".join(lines) + "\n")


def build_summary(repos: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "hybrid_wins": 0,
        "original_wins": 0,
        "ties": 0,
    }
    for repo in repos:
        for task in repo["tasks"]:
            winner = task.get("winner")
            if winner == "hybrid":
                summary["hybrid_wins"] += 1
            elif winner == "original":
                summary["original_wins"] += 1
            else:
                summary["ties"] += 1
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare the original C tool against the hybrid Zig port on the same repo tasks.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--zig-bin", required=True)
    parser.add_argument("--c-bin", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    manifest_path = Path(args.manifest).resolve()
    root_dir = Path(args.root).resolve()
    report_dir = Path(args.report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(manifest_path.read_text())
    repos = [
        run_repo(
            repo=repo,
            root_dir=root_dir,
            zig_bin=args.zig_bin,
            c_bin=args.c_bin,
        )
        for repo in manifest.get("repos", [])
    ]
    report = {
        "manifest": str(manifest_path),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": os.uname().nodename,
        "repos": repos,
        "summary": build_summary(repos),
    }

    json_path = report_dir / "agent_comparison_report.json"
    md_path = report_dir / "agent_comparison_report.md"
    json_path.write_text(json.dumps(report, indent=2))
    write_markdown(report, md_path)

    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
