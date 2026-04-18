#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any

from repo_sources import resolve_repo_source
from run_benchmark_suite import create_runtime_env, indexed_project_name, run_cli_tool, summarize_measurements


AGENTS = (
    ("original", "c"),
    ("hybrid", "zig"),
)

KEY_ALIASES = {
    "total": {"total", "total_results"},
    "file_path": {"file_path", "file"},
}


def normalized_stderr_lines(stderr: str) -> list[str]:
    return [line.strip() for line in stderr.splitlines() if line.strip()]


def extract_error_info(result: dict[str, Any]) -> dict[str, Any]:
    payload = result.get("payload")
    payload_reason = ""
    payload_code: int | None = None
    if isinstance(payload, dict) and payload.get("__error__"):
        payload_reason = str(payload["__error__"])
    elif isinstance(payload, dict) and isinstance(payload.get("error"), dict):
        payload_error = payload["error"]
        payload_code = int(payload_error["code"]) if isinstance(payload_error.get("code"), int) else None
        payload_reason = str(payload_error.get("message") or payload_error)

    stderr_lines = normalized_stderr_lines(str(result.get("stderr", "")))
    returncode = int(result.get("returncode", 0))
    return {
        "present": bool(returncode != 0 or payload_reason),
        "returncode": returncode,
        "payload_code": payload_code,
        "payload_reason": payload_reason or None,
        "stderr_summary": (stderr_lines[-1] if stderr_lines else None),
        "stderr_tail": stderr_lines[-5:],
    }


def compare_error_info(original: dict[str, Any], hybrid: dict[str, Any]) -> dict[str, Any]:
    if not original["present"] and not hybrid["present"]:
        return {"status": "none"}

    if original["present"] != hybrid["present"]:
        return {
            "status": "mismatch",
            "differences": ["presence"],
            "original": original,
            "hybrid": hybrid,
        }

    differences: list[str] = []
    if original.get("payload_code") != hybrid.get("payload_code"):
        differences.append("payload_code")
    if original.get("payload_reason") != hybrid.get("payload_reason"):
        differences.append("payload_reason")
    if original.get("stderr_summary") != hybrid.get("stderr_summary"):
        differences.append("stderr_summary")
    if original.get("returncode") != hybrid.get("returncode"):
        differences.append("returncode")

    return {
        "status": ("match" if not differences else "mismatch"),
        "differences": differences,
        "original": original,
        "hybrid": hybrid,
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


def grade_payload(payload: Any, expect: dict[str, Any], error: dict[str, Any]) -> dict[str, Any]:
    if expect.get("expect_error"):
        if not error.get("present"):
            return {"status": "FAIL", "score": 0.0, "details": {"reason": "expected error"}}

        required_error_substrings = [str(item) for item in expect.get("error_substrings", [])]
        if not required_error_substrings:
            return {"status": "PASS", "score": 1.0, "details": {"error": error}}

        haystack = " ".join(
            part
            for part in [
                str(error.get("payload_reason") or ""),
                str(error.get("stderr_summary") or ""),
                " ".join(str(line) for line in error.get("stderr_tail", [])),
            ]
            if part
        )
        missing = [item for item in required_error_substrings if item not in haystack]
        passed = len(required_error_substrings) - len(missing)
        if not missing:
            return {"status": "PASS", "score": 1.0, "details": {"missing_error_substrings": missing}}
        if passed > 0:
            return {"status": "PARTIAL", "score": round(passed / len(required_error_substrings), 3), "details": {"missing_error_substrings": missing}}
        return {"status": "FAIL", "score": 0.0, "details": {"missing_error_substrings": missing}}

    if error.get("present"):
        return {
            "status": "FAIL",
            "score": 0.0,
            "details": {
                "reason": error.get("payload_reason") or error.get("stderr_summary") or "command failed",
            },
        }

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
    project_override: str,
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
            project_override=project_override,
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
                project_override=project_override,
            )
        )

    payload = measurements[-1].get("payload")
    error = extract_error_info(measurements[-1])
    return {
        "tool": task_tool,
        "args": task_args,
        "payload": payload,
        "error": error,
        "grade": grade_payload(payload, dict(task.get("expect", {})), error),
        "summary": summarize_measurements(measurements),
        "measurements": measurements,
    }


def build_error_summary(tasks: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "original_errors": 0,
        "hybrid_errors": 0,
        "matches": 0,
        "mismatches": 0,
    }
    for task in tasks:
        if task["original"]["error"]["present"]:
            summary["original_errors"] += 1
        if task["hybrid"]["error"]["present"]:
            summary["hybrid_errors"] += 1
        status = task.get("error_comparison", {}).get("status")
        if status == "match":
            summary["matches"] += 1
        elif status == "mismatch":
            summary["mismatches"] += 1
    return summary


def build_session_steps(repo: dict[str, Any], label: str) -> list[dict[str, Any]]:
    index_result = repo["index"][label]
    steps = [
        {
            "id": "index-repository",
            "prompt": "Index the repository before running the explorer session.",
            "tool": "index_repository",
            "args": {},
            "payload": index_result.get("payload"),
            "error": extract_error_info(index_result),
            "returncode": index_result.get("returncode"),
            "elapsed_ms": round(float(index_result.get("elapsed_ms", 0.0)), 3),
        }
    ]
    for task in repo["tasks"]:
        result = task[label]
        steps.append(
            {
                "id": task["id"],
                "prompt": task.get("prompt", ""),
                "tool": task["tool"],
                "args": result["args"],
                "expect": task.get("expect", {}),
                "grade": result["grade"],
                "summary": result["summary"],
                "error": result["error"],
                "payload": result["payload"],
            }
        )
    return steps


def write_session_artifacts(repos: list[dict[str, Any]], report_dir: Path) -> None:
    sessions_dir = report_dir / "sessions"
    for repo in repos:
        repo_dir = sessions_dir / str(repo["id"])
        repo_dir.mkdir(parents=True, exist_ok=True)

        original_path = repo_dir / "original.json"
        hybrid_path = repo_dir / "hybrid.json"
        comparison_path = repo_dir / "comparison.json"

        original_doc = {
            "repo": repo["id"],
            "path": repo["path"],
            "implementation": "original",
            "steps": build_session_steps(repo, "original"),
        }
        hybrid_doc = {
            "repo": repo["id"],
            "path": repo["path"],
            "implementation": "hybrid",
            "steps": build_session_steps(repo, "hybrid"),
        }
        comparison_doc = {
            "repo": repo["id"],
            "path": repo["path"],
            "error_summary": repo["error_summary"],
            "tasks": [
                {
                    "id": task["id"],
                    "tool": task["tool"],
                    "winner": task["winner"],
                    "error_comparison": task["error_comparison"],
                }
                for task in repo["tasks"]
            ],
        }

        original_path.write_text(json.dumps(original_doc, indent=2))
        hybrid_path.write_text(json.dumps(hybrid_doc, indent=2))
        comparison_path.write_text(json.dumps(comparison_doc, indent=2))

        repo["session_artifacts"] = {
            "original": str(original_path),
            "hybrid": str(hybrid_path),
            "comparison": str(comparison_path),
        }


def run_repo(
    *,
    repo: dict[str, Any],
    root_dir: Path,
    zig_bin: str,
    c_bin: str,
    source_cache_dir: Path,
) -> dict[str, Any]:
    resolved_repo = resolve_repo_source(repo, root_dir, source_cache_dir)
    repo_abs = Path(resolved_repo["path"])
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
        indexed_projects: dict[str, str] = {}
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
            indexed_projects[label] = indexed_project_name(index_results[label], repo_abs, repo, impl)

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
                project_override=indexed_projects["original"],
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
                project_override=indexed_projects["hybrid"],
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
                    "error_comparison": compare_error_info(original["error"], hybrid["error"]),
                }
            )

        return {
            "id": repo["id"],
            "path": str(repo_abs),
            "source": resolved_repo["source"],
            "notes": list(repo.get("notes", [])),
            "index": {
                "original": index_results["original"],
                "hybrid": index_results["hybrid"],
            },
            "tasks": tasks,
            "error_summary": build_error_summary(tasks),
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
        f"- Suite files: `{len(report.get('manifest_sources', []))}`",
        f"- Repos run: `{len(report['repos'])}`",
        f"- Hybrid wins: `{overall['hybrid_wins']}`",
        f"- Original wins: `{overall['original_wins']}`",
        f"- Ties: `{overall['ties']}`",
        f"- Error matches: `{overall['error_matches']}`",
        f"- Error mismatches: `{overall['error_mismatches']}`",
        "",
        "| Repo | Task | Tool | Original Grade | Hybrid Grade | Error Parity | Original Median (ms) | Hybrid Median (ms) | Winner |",
        "|------|------|------|----------------|--------------|--------------|---------------------:|-------------------:|--------|",
    ]

    for repo in report["repos"]:
        for task in repo["tasks"]:
            lines.append(
                "| {repo} | {task_id} | {tool} | {orig_grade} | {hybrid_grade} | {error_status} | {orig_ms} | {hybrid_ms} | {winner} |".format(
                    repo=repo["id"],
                    task_id=task["id"],
                    tool=task["tool"],
                    orig_grade=task["original"]["grade"]["status"],
                    hybrid_grade=task["hybrid"]["grade"]["status"],
                    error_status=task.get("error_comparison", {}).get("status", "none"),
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
        lines.append(
            "- Error summary: `original={orig}` `hybrid={hybrid}` `matches={matches}` `mismatches={mismatches}`".format(
                orig=repo["error_summary"]["original_errors"],
                hybrid=repo["error_summary"]["hybrid_errors"],
                matches=repo["error_summary"]["matches"],
                mismatches=repo["error_summary"]["mismatches"],
            )
        )
        if repo.get("session_artifacts"):
            lines.append(
                "- Session artifacts: `original={orig}` `hybrid={hybrid}` `comparison={comparison}`".format(
                    orig=repo["session_artifacts"]["original"],
                    hybrid=repo["session_artifacts"]["hybrid"],
                    comparison=repo["session_artifacts"]["comparison"],
                )
            )
        lines.extend(
            [
                "",
                "| Task | Tool | Original | Hybrid | Error Parity | Winner |",
                "|------|------|----------|--------|--------------|--------|",
            ]
        )
        for task in repo["tasks"]:
            lines.append(
                "| {task_id} | {tool} | {orig} ({orig_ms} ms) | {hybrid} ({hybrid_ms} ms) | {error_status} | {winner} |".format(
                    task_id=task["id"],
                    tool=task["tool"],
                    orig=task["original"]["grade"]["status"],
                    hybrid=task["hybrid"]["grade"]["status"],
                    orig_ms=task["original"]["summary"].get("median_ms", "n/a"),
                    hybrid_ms=task["hybrid"]["summary"].get("median_ms", "n/a"),
                    error_status=task.get("error_comparison", {}).get("status", "none"),
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
        "error_matches": 0,
        "error_mismatches": 0,
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
            error_status = task.get("error_comparison", {}).get("status")
            if error_status == "match":
                summary["error_matches"] += 1
            elif error_status == "mismatch":
                summary["error_mismatches"] += 1
    return summary


def load_manifest_file(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text())
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be an object: {path}")
    repos = manifest.get("repos", [])
    if not isinstance(repos, list):
        raise ValueError(f"manifest repos must be a list: {path}")
    return manifest


def load_manifest_sources(path: Path) -> tuple[dict[str, Any], list[str]]:
    if path.is_file():
        manifest = load_manifest_file(path)
        return manifest, [str(path)]

    if not path.is_dir():
        raise FileNotFoundError(f"manifest path does not exist: {path}")

    manifests = sorted(path.glob("*.json"))
    if not manifests:
        raise ValueError(f"manifest directory has no .json files: {path}")

    merged: dict[str, Any] = {
        "schema_version": "0.1",
        "goal": f"Merged agent comparison suites from {path}",
        "repos": [],
    }
    sources: list[str] = []
    seen_repo_ids: set[str] = set()
    for manifest_path in manifests:
        manifest = load_manifest_file(manifest_path)
        sources.append(str(manifest_path))
        for repo in manifest.get("repos", []):
            repo_id = str(repo.get("id", ""))
            if not repo_id:
                raise ValueError(f"repo is missing id in {manifest_path}")
            if repo_id in seen_repo_ids:
                raise ValueError(f"duplicate repo id {repo_id!r} across manifest sources")
            seen_repo_ids.add(repo_id)
            merged["repos"].append(repo)
    return merged, sources


def filter_repos(manifest: dict[str, Any], repo_ids: list[str]) -> dict[str, Any]:
    if not repo_ids:
        return manifest

    requested = set(repo_ids)
    repos = [repo for repo in manifest.get("repos", []) if str(repo.get("id", "")) in requested]
    found = {str(repo.get("id", "")) for repo in repos}
    missing = sorted(requested - found)
    if missing:
        raise ValueError(f"unknown repo ids requested: {', '.join(missing)}")

    filtered = dict(manifest)
    filtered["repos"] = repos
    return filtered


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare the original C tool against the hybrid Zig port on the same repo tasks.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--zig-bin", required=True)
    parser.add_argument("--c-bin", required=True)
    parser.add_argument("--report-dir", required=True)
    parser.add_argument("--source-cache-dir", default="")
    parser.add_argument("--repo-id", action="append", default=[], help="Limit the run to one or more repo ids from the suite set")
    args = parser.parse_args()

    manifest_path = Path(args.manifest).resolve()
    root_dir = Path(args.root).resolve()
    report_dir = Path(args.report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    source_cache_dir = Path(args.source_cache_dir).resolve() if args.source_cache_dir else (root_dir / ".corpus_cache")

    manifest, sources = load_manifest_sources(manifest_path)
    manifest = filter_repos(manifest, list(args.repo_id))
    repos = [
        run_repo(
            repo=repo,
            root_dir=root_dir,
            zig_bin=args.zig_bin,
            c_bin=args.c_bin,
            source_cache_dir=source_cache_dir,
        )
        for repo in manifest.get("repos", [])
    ]
    write_session_artifacts(repos, report_dir)
    report = {
        "manifest": str(manifest_path),
        "manifest_sources": sources,
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
