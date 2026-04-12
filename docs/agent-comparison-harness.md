# Agent Comparison Harness

Use `scripts/run_agent_comparison.sh` to compare the original C implementation against the hybrid Zig port on the same repository tasks.

The harness is intentionally ordered:

1. Original C tool
2. Hybrid Zig tool

Each repository in `testdata/agent-comparison/manifest.json` defines:

- `path`: repository under test
- `project`: stable Zig-side project id
- `warmup_runs` and `measured_runs`
- `tasks`: shared agent-style prompts, MCP tool name, tool args, and scoring expectations

Run it with:

```sh
bash scripts/run_agent_comparison.sh
```

Optional overrides:

```sh
CODEBASE_MEMORY_C_BIN=/path/to/codebase-memory-mcp \
CODEBASE_MEMORY_ZIG_BIN=/path/to/cbm \
bash scripts/run_agent_comparison.sh /path/to/manifest.json /path/to/report-dir
```

Outputs:

- `.agent_comparison_reports/agent_comparison_report.json`
- `.agent_comparison_reports/agent_comparison_report.md`

Scoring rules:

- `PASS`: the implementation met every expectation for the task
- `PARTIAL`: it returned a useful result but missed one or more expected fields or facts
- `FAIL`: it failed the task or returned an error payload

Winner selection:

- higher task score wins first
- if scores tie, lower median latency wins

This keeps the MCP surface stable while letting us validate whether the hybrid internals improve retrieval quality, architecture answers, and latency on the same tasks.
