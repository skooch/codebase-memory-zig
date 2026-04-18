#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ITERATIONS=5
REPORT_DIR="$ROOT_DIR/.soak_reports"
POSITIONAL_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --iterations)
      ITERATIONS="${2:?--iterations requires a value}"
      shift 2
      ;;
    --report-dir)
      REPORT_DIR="${2:?--report-dir requires a value}"
      shift 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL_ARGS[@]}" -gt 0 ]; then
  ITERATIONS="${POSITIONAL_ARGS[0]}"
fi

if [ -n "${CODEBASE_MEMORY_ZIG_BIN:-}" ]; then
  ZIG_BIN="$CODEBASE_MEMORY_ZIG_BIN"
else
  zig build >/dev/null
  ZIG_BIN="$ROOT_DIR/zig-out/bin/cbm"
fi

mkdir -p "$REPORT_DIR"

python3 - "$ZIG_BIN" "$REPORT_DIR" "$ITERATIONS" <<'PY'
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

zig_bin = Path(sys.argv[1]).resolve()
report_dir = Path(sys.argv[2]).resolve()
iterations = int(sys.argv[3])

report_dir.mkdir(parents=True, exist_ok=True)

def measure(argv, env, cwd):
    start = time.perf_counter()
    proc = subprocess.run(argv, cwd=cwd, env=env, text=True, capture_output=True, check=False)
    elapsed_ms = round((time.perf_counter() - start) * 1000.0, 3)
    return proc, elapsed_ms


def percentile(values, pct):
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    pos = (len(ordered) - 1) * pct
    lower = int(pos)
    upper = min(lower + 1, len(ordered) - 1)
    if lower == upper:
        return ordered[lower]
    weight = pos - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


with tempfile.TemporaryDirectory(prefix="cbm-soak-") as tmp:
    tmp_root = Path(tmp)
    home = tmp_root / "home"
    cache_dir = home / ".cache" / "codebase-memory-zig"
    repo = tmp_root / "soak-repo"
    report_file = report_dir / "soak_report.json"
    summary_file = report_dir / "soak_report.md"
    home.mkdir(parents=True, exist_ok=True)
    repo.mkdir(parents=True, exist_ok=True)
    (repo / "src").mkdir()

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["CBM_CACHE_DIR"] = str(cache_dir)

    for idx in range(1, 7):
        (repo / "src" / f"service_{idx}.py").write_text(
            "from helper import normalize_value\n\n"
            f"class Service{idx}:\n"
            "    def __init__(self, value):\n"
            "        self.value = value\n\n"
            "    def handle(self):\n"
            "        return normalize_value(self.value)\n"
        )
    (repo / "src" / "helper.py").write_text(
        "def normalize_value(value):\n"
        "    return str(value).strip().lower()\n"
    )
    (repo / "README.md").write_text("# Soak Repo\n")

    subprocess.run(["git", "init", "-q"], cwd=repo, check=True, capture_output=True, text=True)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True, capture_output=True, text=True)
    subprocess.run(
        ["git", "-c", "user.email=soak@test", "-c", "user.name=soak", "commit", "-q", "-m", "init"],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )

    project_name = repo.name
    results = []
    failures = []

    for iteration in range(1, iterations + 1):
        target = repo / "src" / f"service_{(iteration % 6) + 1}.py"
        with target.open("a", encoding="utf-8") as handle:
            handle.write(
                "\n"
                f"def soak_tick_{iteration}():\n"
                f"    return Service{(iteration % 6) + 1}({iteration}).handle()\n"
            )
        subprocess.run(["git", "add", "-A"], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(
            ["git", "-c", "user.email=soak@test", "-c", "user.name=soak", "commit", "-q", "-m", f"tick-{iteration}"],
            cwd=repo,
            check=True,
            capture_output=True,
            text=True,
        )

        index_proc, index_ms = measure(
            [str(zig_bin), "cli", "index_repository", json.dumps({"project_path": str(repo)})],
            env,
            repo,
        )
        search_proc, search_ms = measure(
            [str(zig_bin), "cli", "search_graph", json.dumps({"project": project_name, "name_pattern": "Service", "limit": 20})],
            env,
            repo,
        )
        arch_proc, arch_ms = measure(
            [str(zig_bin), "cli", "get_architecture", json.dumps({"project": project_name, "aspects": ["packages", "hotspots"]})],
            env,
            repo,
        )

        search_payload = {}
        try:
            search_payload = json.loads(search_proc.stdout)
        except json.JSONDecodeError:
            search_payload = {}

        search_total = 0
        if isinstance(search_payload.get("result"), dict):
            search_total = int(search_payload["result"].get("total", 0) or 0)

        iteration_result = {
            "iteration": iteration,
            "index_ms": index_ms,
            "search_ms": search_ms,
            "architecture_ms": arch_ms,
            "index_returncode": index_proc.returncode,
            "search_returncode": search_proc.returncode,
            "architecture_returncode": arch_proc.returncode,
            "search_total": search_total,
        }
        results.append(iteration_result)

        if index_proc.returncode != 0 or search_proc.returncode != 0 or arch_proc.returncode != 0:
            failures.append(
                {
                    "iteration": iteration,
                    "index_stderr": index_proc.stderr.splitlines()[-5:],
                    "search_stderr": search_proc.stderr.splitlines()[-5:],
                    "architecture_stderr": arch_proc.stderr.splitlines()[-5:],
                }
            )
            continue

        if search_total <= 0:
            failures.append({"iteration": iteration, "reason": "search_graph returned no results"})

    index_values = [entry["index_ms"] for entry in results]
    search_values = [entry["search_ms"] for entry in results]
    arch_values = [entry["architecture_ms"] for entry in results]
    report = {
        "binary": str(zig_bin),
        "iterations": iterations,
        "project": str(repo),
        "failures": failures,
        "summary": {
            "index_median_ms": round(statistics.median(index_values), 3) if index_values else 0.0,
            "index_p95_ms": round(percentile(index_values, 0.95), 3) if index_values else 0.0,
            "search_median_ms": round(statistics.median(search_values), 3) if search_values else 0.0,
            "architecture_median_ms": round(statistics.median(arch_values), 3) if arch_values else 0.0,
        },
        "iterations_detail": results,
    }

    report_file.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary_lines = [
        "# Soak Suite Report",
        "",
        f"- Binary: `{zig_bin}`",
        f"- Iterations: `{iterations}`",
        f"- Failures: `{len(failures)}`",
        f"- Index median: `{report['summary']['index_median_ms']}` ms",
        f"- Index p95: `{report['summary']['index_p95_ms']}` ms",
        f"- Search median: `{report['summary']['search_median_ms']}` ms",
        f"- Architecture median: `{report['summary']['architecture_median_ms']}` ms",
        "",
        "| Iteration | Index (ms) | Search (ms) | Architecture (ms) | Search Total |",
        "|-----------|-----------:|------------:|------------------:|-------------:|",
    ]
    for entry in results:
        summary_lines.append(
            f"| {entry['iteration']} | {entry['index_ms']} | {entry['search_ms']} | {entry['architecture_ms']} | {entry['search_total']} |"
        )
    summary_file.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    print(f"Wrote {report_file}")
    print(f"Wrote {summary_file}")
    if failures:
        raise SystemExit(1)
PY
