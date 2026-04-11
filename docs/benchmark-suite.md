# Benchmark Suite

This repo now has a first-slice benchmark lane that compares `codebase-memory-zig` against the original `codebase-memory-mcp` on:

- task-scored accuracy for a shared local fixture set
- cold indexing time
- warm query time
- peak RSS during measured runs

It intentionally complements the existing interoperability harness instead of replacing it:

- `scripts/run_interop_alignment.sh` stays the strict parity gate
- `scripts/run_benchmark_suite.sh` is the broader benchmark lane

## Run It

```sh
bash scripts/run_benchmark_suite.sh
```

Optional arguments:

```sh
bash scripts/run_benchmark_suite.sh testdata/bench/manifest.json .benchmark_reports
```

Defaults:

- manifest: `testdata/bench/manifest.json`
- report dir: `.benchmark_reports/`

The shell wrapper will:

- build the Zig binary in `ReleaseFast` unless `CODEBASE_MEMORY_ZIG_BIN` is set
- use `../codebase-memory-mcp/build/c/codebase-memory-mcp` unless `CODEBASE_MEMORY_C_BIN` is set
- write JSON and Markdown reports into the chosen report directory

## What The First Slice Covers

Accuracy-scored fixture repos:

- `python-basic`
- `javascript-basic`
- `typescript-basic`
- `rust-basic`
- `zig-basic`

Performance-oriented local repo:

- `codebase-memory-zig`

Shared tools covered in the first slice:

- `index_repository`
- `search_graph`
- `query_graph`
- `trace_call_path`
- `search_code`

Accuracy scoring is scenario-based:

- `PASS` = full expectation met
- `PARTIAL` = some expectation met
- `FAIL` = expectation not met

This keeps the benchmark suite useful on larger repos where full canonical payload equality would be too noisy to treat as the benchmark signal.

## Fairness Rules

Each measured run:

- gets its own temporary `HOME`
- gets its own `CBM_CACHE_DIR`
- uses a fresh runtime DB for cold index timing
- re-indexes into a fresh runtime before measured query timing

That means:

- cold index timings are isolated
- query timings are measured after indexing, not against a reused machine-local cache

## Reports

The runner writes:

- `benchmark_report.json`
- `benchmark_report.md`

The Markdown report includes:

- per-repo accuracy comparison
- median cold index timings
- median query timings
- a simple faster/slower comparison for cold indexing

## Current Limits

This is the initial runnable slice, not the finished benchmark program.

Current limits:

- the default manifest uses only local repos already available in this workspace
- timing is CLI-based, not persistent in-session MCP timing
- large external benchmark repos and pinned remote clone workflows are still future work
- the benchmark lane scores a shared scenario contract; it does not try to diff every payload field the way the interop lane does
