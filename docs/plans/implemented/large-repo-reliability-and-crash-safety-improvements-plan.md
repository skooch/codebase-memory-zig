# Plan: Large-Repo Reliability and Crash Safety Improvements

## Goal
Harden the Zig port against the same large-repository failure modes that repeatedly hit the C implementation: OOMs, traversal overflows, lockups, silent truncation, DB corruption, and race-prone lifecycle behavior.

## Research Basis

Upstream issue families captured in this plan:
- Sustained CPU, hang, and OOM reports: `#41`, `#45`, `#49`, `#52`, `#58`, `#141`, `#195`
- Crash safety and corruption during indexing: `#62`, `#67`, `#116`, `#139`, `#187`, `#189`
- Query or RPC hangs from buffering and lock contention: `#98`, `#100`, `#119`, `#125`
- Scale-sensitive parser or traversal failures: `#70`, `#71`, `#105`, `#106`, `#130`, `#169`, `#199`, `#212`, `#215`, `#235`
- Lifecycle instability or leaked processes: `#50`, `#127`

Upstream PRs that show the likely implementation shape:
- OOM and pool-pressure control: `#59`
- Crash-safe journal handling: `#68`, `#72`, `#117`
- Buffered I/O and handler hang fixes: `#99`, `#109`, `#120`, `#126`
- Traversal performance and overflow removal: `#107`, `#131`, `#217`
- Race and spin-loop cleanup: `#191`, `#192`, `#193`, `#194`, `#207`
- SQLite writer and memory-safety follow-ons: `#175`, `#206`, `#209`, `#210`
- Search-result size guardrails: `#170`, `#231`

Observed upstream pattern:
- Reliability regressions were usually not one bug; they were interactions between memory pressure, fixed-size traversal stacks, buffering mismatches, and unsafe bulk-write assumptions.
- The durable upstream fixes added explicit caps, growable structures, earlier release points, and verified stress harnesses instead of relying on “average repo” assumptions.

## Current Phase
Implemented

## File Map
- Modify: `docs/plans/implemented/large-repo-reliability-and-crash-safety-improvements-plan.md`
- Create: `docs/plans/implemented/large-repo-reliability-and-crash-safety-improvements-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/pipeline.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/store.zig`
- Modify: `src/mcp.zig`
- Modify: `src/runtime_lifecycle.zig`
- Modify: `src/watcher.zig`
- Modify: `scripts/run_benchmark_suite.sh`
- Modify: `scripts/test_runtime_lifecycle.sh`
- Create: `testdata/bench/stress-manifest.json`
- Create: `testdata/bench/stress/README.md`

## Phases

### Phase 1: Lock the Stress and Failure Matrix
- [x] Convert the upstream crash classes into a Zig-side reproduction matrix in `docs/gap-analysis.md`, separating memory pressure, traversal overflow, store corruption, and lifecycle hangs.
- [x] Add a local stress manifest and documentation under `testdata/bench/stress/` so large-repo checks are reproducible without depending on external monorepos.
- [x] Record target metrics, red-line thresholds, exact verification commands, and the first baseline results in `docs/plans/implemented/large-repo-reliability-and-crash-safety-improvements-progress.md`.
- **Status:** complete

### Phase 2: Add Explicit Guardrails
- [x] Strengthen `src/pipeline.zig`, `src/graph_buffer.zig`, and `src/store.zig` with explicit size guards, early-release points, crash-safe transactional behavior, and growable traversal state where the current design still assumes moderate file or result sizes.
- [x] Tighten `src/mcp.zig`, `src/runtime_lifecycle.zig`, and `src/watcher.zig` so request framing, shutdown, watcher concurrency, and status reporting stay deterministic under load instead of relying on incidental sequencing.
- [x] Add backpressure, timeout, and oversized-response behavior that fails cleanly and observably rather than silently truncating or wedging the runtime.
- **Status:** complete

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, `bash scripts/run_benchmark_suite.sh`, and `bash scripts/test_runtime_lifecycle.sh` with the new stress cases until resource usage and failure handling stay bounded.
- [x] Update `docs/port-comparison.md` only for the rows that have explicit stress evidence rather than anecdotal “seems stable” claims.
- [x] Record remaining scale risks, skipped stress lanes, and next follow-on work in `docs/plans/implemented/large-repo-reliability-and-crash-safety-improvements-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat stress verification as a completion gate, not a nice-to-have | The upstream history shows that green unit tests did not prevent real-world OOMs, corruption, or hangs. |
| Prefer explicit bounds and growable structures over silent truncation | Silent drop behavior created several of the most damaging upstream trust failures. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `scripts/run_benchmark_suite.sh` failed before launching the Python harness | The first Phase 1 baseline run hit `EXTRA_ARGS[@]: unbound variable` under `set -u` when no trailing args were forwarded | Guard the no-extra-args path explicitly in the shell wrapper and record the failure mode in `CLAUDE.md` before rerunning the benchmark. |
