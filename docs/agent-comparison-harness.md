# Agent Comparison Harness

Use `scripts/run_agent_comparison.zsh` to compare the original C implementation against the hybrid Zig port on the same repository tasks.

The harness is intentionally ordered:

1. Original C tool
2. Hybrid Zig tool

The harness now loads either:

- a single manifest file
- or a directory of suite files

By default it reads every `*.json` file in `testdata/agent-comparison/suites/`.

Each suite file defines one or more repositories with:

- `path`: repository under test
- `project`: stable Zig-side project id
- `warmup_runs` and `measured_runs`
- `tasks`: shared agent-style prompts, MCP tool name, tool args, and scoring expectations

Optional source forms:

- local checkout via `path`
- pinned GitHub checkout via `github.repo` + `github.ref`

Each repo run is also treated as a recorded explorer session:

- the harness indexes once per implementation
- runs the task list in order against that indexed runtime
- writes per-implementation session transcripts plus a task-level error comparison file

Run it with:

```sh
zsh scripts/run_agent_comparison.zsh
```

Optional overrides:

```sh
CODEBASE_MEMORY_C_BIN=/path/to/codebase-memory-mcp \
CODEBASE_MEMORY_ZIG_BIN=/path/to/cbm \
zsh scripts/run_agent_comparison.zsh /path/to/manifest-or-suite-dir /path/to/report-dir
```

Run a subset of configured repos without editing the suite files:

```sh
zsh scripts/run_agent_comparison.zsh \
  testdata/agent-comparison/suites \
  .agent_comparison_reports \
  --repo-id python-basic \
  --repo-id scip-overlay
```

Outputs:

- `.agent_comparison_reports/agent_comparison_report.json`
- `.agent_comparison_reports/agent_comparison_report.md`
- `.agent_comparison_reports/sessions/<repo-id>/original.json`
- `.agent_comparison_reports/sessions/<repo-id>/hybrid.json`
- `.agent_comparison_reports/sessions/<repo-id>/comparison.json`

Pinned GitHub suites are materialized into `.corpus_cache/` and reused across runs.

Scoring rules:

- `PASS`: the implementation met every expectation for the task
- `PARTIAL`: it returned a useful result but missed one or more expected fields or facts
- `FAIL`: it failed the task or returned an error payload

Error assertions:

- add `"expect_error": true` inside a task's `expect` object to require a failure instead of a success payload
- optional `"error_substrings"` lets the suite require specific stderr or payload fragments
- the report marks each task with `Error Parity` so mismatched failures are obvious even when both implementations score `FAIL`

Winner selection:

- higher task score wins first
- if scores tie, lower median latency wins

Recommended layout:

- one suite file per reusable fixture or repo class
- keep prompts and expectations close to that repo
- compose larger runs by pointing the harness at the suite directory

Pinned GitHub suite example:

```sh
zsh scripts/run_agent_comparison.zsh \
  testdata/agent-comparison/suites/github-large.json \
  .agent_comparison_reports/github-large \
  --repo-id flask
```

This keeps the MCP surface stable while letting us validate whether the hybrid internals improve retrieval quality, architecture answers, and latency on the same tasks.
