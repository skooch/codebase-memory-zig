# Plan: Shared Capability Phase 2 Sequencing

## Goal
Execute the next shared-capability parity slice in an order that maximizes dependency reuse, keeps verification stable, and flips the remaining Phase 2 protocol/query rows in `docs/port-comparison.md` from `Interoperable? No` to `Yes`.

## Current Phase
Completed

## File Map
- Create: `docs/plans/new/shared-capability-phase-2-sequencing-plan.md`
- Modify: `docs/plans/in-progress/shared-capability-parity-plan.md`
- Modify: `docs/plans/in-progress/shared-capability-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/cypher.zig`
- Modify: `src/store.zig`
- Modify: `src/mcp.zig`
- Modify: `src/main.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`

## Phases

### Phase 1: Expand `query_graph` to the Shared Full-Parity Floor
- [x] Re-read the `query_graph`, `get_architecture`, `search_code`, and `detect_changes` rows in `docs/port-comparison.md` and `docs/gap-analysis.md`, then pin the exact overlapping read-only query shapes the original exposes and the Zig port still rejects or mis-shapes.
- [x] Extend `testdata/interop/manifest.json` and `scripts/run_interop_alignment.sh` so the harness runs an explicit `query_graph` parity suite covering the shared read-only forms that Phase 2 depends on: filtering, sorting, counts, projected columns, and deterministic row ordering.
- [x] Update `src/cypher.zig`, `src/store.zig`, and `src/mcp.zig` so those overlapping query forms return the same columns, row ordering, and error semantics as the original on the parity fixtures.
- [x] Add or extend targeted regression tests in `src/cypher.zig`, `src/store.zig`, and `src/mcp.zig`, then re-run `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh` to establish a new green `query_graph` baseline before touching its downstream consumers.
- **Status:** completed

### Phase 2: Lift `get_architecture` onto the Broadened Query Contract
- [x] Use the new Phase 1 `query_graph` coverage to identify which richer `get_architecture` sections are already shared and should now be promoted from “practical summary” to parity contract.
- [x] Update `src/mcp.zig` and, only where required, `src/store.zig` so `get_architecture` returns the same overlapping sections, counts, and structured fields as the original for the parity fixtures and focused repo probes.
- [x] Extend `scripts/run_interop_alignment.sh` and `testdata/interop/manifest.json` with canonicalized `get_architecture` assertions for those richer shared sections, keeping any still-original-only sections explicitly outside the asserted contract.
- [x] Re-run `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh`, then update the affected Phase 2 notes in `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` only if the new architecture assertions are green.
- **Status:** completed

### Phase 3: Close the Remaining Output-Shaping Gaps in `search_code` and `detect_changes`
- [x] Update `src/mcp.zig` and `src/store.zig` so `search_code` matches the original’s overlapping grouping, dedup into containing symbols, and ranking behavior across the parity fixtures rather than only the currently asserted subset.
- [x] Update `src/mcp.zig` and any supporting query/store paths so `detect_changes` adds the original’s overlapping risk/reporting metadata while preserving the already-aligned mode-style `scope` contract.
- [x] Extend `testdata/interop/manifest.json` and `scripts/run_interop_alignment.sh` with broader `search_code` and controlled dirty-worktree `detect_changes` assertions that prove these output-shaping changes against the original instead of against hand-written expectations alone.
- [x] Re-run `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh`, then update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` if the shared `search_code` and `detect_changes` rows now meet the full-parity acceptance rules.
- **Status:** completed

### Phase 4: Finish the Sidecar `cli --progress` Parity Work
- [x] Capture the original CLI progress event stream for the shared commands already covered by the temp-HOME installer and interop checks, then normalize the exact overlapping phase names, ordering, and payload fields Zig must emit.
- [x] Update `src/main.zig` and `src/mcp.zig` so `cli --progress` emits the richer phase-aware event stream without regressing the now-stable tool behavior from Phases 1 through 3.
- [x] Add or extend CLI-side regression checks and temp-HOME parity probes so progress-stream differences fail loudly and independently of MCP payload mismatches.
- [x] Re-run the targeted CLI parity checks plus `zig build` and `zig build test`, then update the relevant docs only if the progress stream now satisfies the shared contract in `docs/gap-analysis.md`.
- **Status:** completed

### Phase 5: Fold the Slice Back into the Umbrella Parity Plan
- [x] Update `docs/plans/in-progress/shared-capability-parity-plan.md` to mark the completed Phase 2 items and carry forward only the still-open protocol/query rows.
- [x] Append the concrete execution log, verification commands, and any remaining blockers to `docs/plans/in-progress/shared-capability-parity-progress.md`.
- [x] Reconcile `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` so their status rows and remaining backlog reflect the completed Phase 2 work exactly once.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Put `query_graph` first | `get_architecture`, `search_code`, and `detect_changes` all depend on richer query/store behavior or are easiest to verify once the query contract is stable. Fixing the query floor first reduces rework in both code and harness assertions. |
| Put `get_architecture` before `search_code` and `detect_changes` | It is the lightest downstream consumer of the broadened query surface and gives a clean confirmation that the richer query contract is usable before tackling ranking and risk-reporting semantics. |
| Keep `search_code` and `detect_changes` in the same slice after `get_architecture` | Both are now primarily output-shaping parity problems, both rely on the same fixture and harness infrastructure, and both benefit from already-stable query semantics. |
| Leave `cli --progress` until after the MCP/query rows stabilize | Progress parity is valuable but largely orthogonal. Doing it last avoids constantly re-recording phase events while the underlying tool behavior and verification flows are still moving. |
| Keep this as a focused sub-plan rather than expanding the umbrella plan again | The umbrella plan already tracks the whole shared-capability program. This document exists to sequence the next few features concretely without mixing them with the later graph-construction and installer phases. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| A stale `zig-out/bin/cbm` masked a `src/main.zig` compile failure after the new progress-stream changes. | The interop harness continued to report the old CLI behavior even though the latest source edit had not built cleanly. | Rebuilt explicitly before rerunning parity checks and documented the stale-binary hazard in `CLAUDE.md` so future work treats harness output as suspicious until the binary is freshly rebuilt. |
| Shared `query_graph` parity still diverged on the JavaScript fixture even after the accepted query shapes were aligned. | Normalized the result payloads and compared the returned rows directly, which isolated the drift to default edge-row ordering rather than to query parsing or filtering. | Changed `src/cypher.zig` to expand edge-query rows in source-node order, matching the original shared contract, and locked that behavior with a regression test. |

## Result

- `cli --progress`, `query_graph`, `get_architecture`, `search_code`, and `detect_changes` are now marked interoperable in the parity docs.
- Final verification baseline for this slice:
  - `zig build`
  - `zig build test`
  - `bash scripts/run_interop_alignment.sh`
  - `Comparisons: 67`
  - `Strict matches: 58`
  - `Diagnostic-only comparisons: 9`
  - `Mismatches: 0`
  - `cli_progress: match`
