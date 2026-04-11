# Progress

## Session: 2026-04-11

### Phase 1: Lock the First Benchmark Slice
- **Status:** complete
- Actions:
  - Moved `docs/plans/new/benchmark-suite-plan.md` to `docs/plans/in-progress/benchmark-suite-plan.md` before implementation.
  - Narrowed the implementation target to a first runnable local benchmark slice with task-scored accuracy and CLI-based performance measurements.

### Phase 2: Build the Benchmark Runner
- **Status:** complete
- Actions:
  - Added `scripts/run_benchmark_suite.sh` to build or reuse the Zig binary, locate the C binary, and launch the Python benchmark runner.
  - Added `scripts/run_benchmark_suite.py` with temp-home isolation, per-implementation CLI adapters, task-scored accuracy checks, cold index timing, warm query timing, peak-RSS capture via `/usr/bin/time -l`, and JSON/Markdown report generation.
  - Added `testdata/bench/manifest.json` with local fixture-scale accuracy scenarios for Python, JavaScript, TypeScript, Rust, and Zig plus a performance-oriented run against the local `codebase-memory-zig` repo.

### Phase 3: Document and Verify the Slice
- **Status:** complete
- Actions:
  - Added `docs/benchmark-suite.md` to explain how the benchmark lane relates to the existing interop lane, how to run it, what it measures, and what the first-slice limits are.
  - Updated `docs/port-comparison.md` so the benchmark row reflects the new first-slice benchmark runner instead of claiming the Zig repo has no benchmark suite at all.
  - Updated `.gitignore` so the new default benchmark report directory, benchmark build artifacts, and Python bytecode output stay out of the worktree by default.
  - Ran `python3 -m py_compile scripts/run_benchmark_suite.py` successfully.
  - Ran `bash scripts/run_benchmark_suite.sh` successfully and verified it wrote `.benchmark_reports/benchmark_report.json` plus `.benchmark_reports/benchmark_report.md`.
  - Fixed a runner bug discovered during the first real benchmark pass: Zig CLI responses were being graded as raw JSON-RPC envelopes instead of unwrapped MCP payloads, which caused false `0%` accuracy and unresolved trace-node lookups. After correcting payload extraction, the benchmark report showed `100%` fixture accuracy for both implementations across the shared local fixture set.
