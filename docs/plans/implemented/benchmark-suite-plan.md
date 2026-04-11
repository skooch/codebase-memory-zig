# Plan: Accuracy and Performance Benchmark Suite

## Status
Implemented on 2026-04-11.

## Goal
Land the first runnable benchmark slice for comparing `codebase-memory-zig` against `codebase-memory-mcp` on:

- task-scored accuracy for a shared local fixture set
- cold indexing time
- warm query time
- peak RSS during measured runs

## Current Phase
Complete

## File Map
- Modify: `docs/plans/implemented/benchmark-suite-plan.md`
- Create: `docs/plans/implemented/benchmark-suite-progress.md`
- Create: `scripts/run_benchmark_suite.sh`
- Create: `scripts/run_benchmark_suite.py`
- Create: `testdata/bench/manifest.json`
- Create: `docs/benchmark-suite.md`
- Modify: `.gitignore`
- Modify: `docs/port-comparison.md`

## Phases

### Phase 1: Lock the First Benchmark Slice
- [x] Move the benchmark plan into `docs/plans/in-progress/` before implementation starts.
- [x] Narrow the implementation target to a first runnable slice instead of the full future benchmark roadmap.
- [x] Define the first-slice file map, repo set, tool set, and verification goals.
- **Status:** complete

### Phase 2: Build the Benchmark Runner
- [x] Add `scripts/run_benchmark_suite.sh` to resolve binaries and launch the benchmark runner.
- [x] Add `scripts/run_benchmark_suite.py` with temp-home isolation, CLI adapters for Zig vs C, accuracy scoring, and timing collection.
- [x] Add `testdata/bench/manifest.json` with local fixture-scale accuracy repos plus at least one performance-oriented local repo.
- **Status:** complete

### Phase 3: Document and Verify the Slice
- [x] Add `docs/benchmark-suite.md` describing scope, usage, fairness rules, and current limits.
- [x] Update `docs/port-comparison.md` so the benchmark-script row reflects the new first-slice benchmark lane.
- [x] Run the benchmark suite and verify that it writes JSON and Markdown reports successfully.
- **Status:** complete

## Verification
- `python3 -m py_compile scripts/run_benchmark_suite.py`
- `bash scripts/run_benchmark_suite.sh`

## Completion Summary
- Added a first runnable benchmark lane separate from the strict interop harness.
- Added a local benchmark manifest that scores shared fixture accuracy and measures cold index plus warm query timing.
- Added JSON and Markdown report generation in `.benchmark_reports/`.
- Verified the runner end-to-end and fixed the Zig CLI payload-unwrapping bug in the benchmark harness before finalizing the slice.

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep benchmarking separate from `scripts/run_interop_alignment.sh` | Strict parity and benchmarking need different scoring models and should not force compromises on each other. |
| Use local repos and fixtures for the first slice | That makes the suite runnable immediately without network setup or a larger corpus bootstrap step. |
| Start with CLI-based timing | It is simpler, comparable across both implementations, and good enough for the first slice. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
