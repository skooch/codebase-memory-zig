# Plan: Full Compare Mismatch Reduction

## Goal
Reduce the current full Zig-vs-C interop mismatch set to zero or to a smaller explicitly documented residual set by fixing the currently observed `get_code_snippet`, `search_graph`, and `query_graph` fixture deltas first.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/01-full-compare-mismatch-reduction-plan.md`
- Create: `docs/plans/new/01-full-compare-mismatch-reduction-progress.md`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/mcp.zig`
- Modify: `src/query_router.zig`
- Modify: `src/cypher.zig`
- Modify: `src/store.zig`
- Modify: `src/query_router_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/python-parity.json`
- Modify: `testdata/interop/golden/javascript-parity.json`
- Modify: `testdata/interop/golden/go-basic.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `testdata/interop/golden/zig-parity.json`
- Modify: `testdata/interop/golden/error-paths.json`

## Phases

### Phase 1: Lock the current mismatch contract
- [ ] Reproduce the current full Zig-vs-C mismatch set with `bash scripts/run_interop_alignment.sh` and write the exact fixture, tool, and category list into `docs/plans/in-progress/01-full-compare-mismatch-reduction-progress.md` once execution starts.
- [ ] Map each mismatch to the responsible surface in `src/query_router.zig`, `src/cypher.zig`, `src/store.zig`, `src/mcp.zig`, or `scripts/run_interop_alignment.sh` so the execution slice is organized by root cause rather than by fixture name alone.
- [ ] Confirm whether each mismatch is a real Zig behavior delta, a harness canonicalization mismatch, or a stale fixture expectation before changing implementation code.
- **Status:** pending

### Phase 2: Fix snippet, search, and query mismatches
- [ ] Update `src/query_router.zig`, `src/store.zig`, and `src/mcp.zig` so `get_code_snippet` matches the intended shared payload contract on the currently failing `python-parity` and `error-paths` cases.
- [ ] Update `src/cypher.zig`, `src/query_router.zig`, and any supporting store logic so the currently failing `query_graph` fixture rows on `javascript-parity`, `go-parity`, and `java-basic` converge toward the shared contract.
- [ ] Update `src/query_router.zig`, `src/store.zig`, or `scripts/run_interop_alignment.sh` canonicalization so the currently failing `search_graph` cases on `go-basic`, `go-parity`, and `zig-parity` align to the intended shared semantics.
- [ ] Add or extend regression coverage in `src/query_router_test.zig`, `src/mcp.zig`, and the affected interop goldens so each fixed mismatch has a stable local proof.
- **Status:** pending

### Phase 3: Rebaseline docs and verify closure
- [ ] Refresh the affected interop goldens under `testdata/interop/golden/` only after the full compare is intentionally improved rather than merely reshaped.
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`, and record the reduced or cleared mismatch set in `docs/plans/in-progress/01-full-compare-mismatch-reduction-progress.md`.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the “remaining mismatch” story reflects the post-fix state rather than the current baseline.
- [x] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the verification results are recorded concretely.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start with the observed mismatch set instead of a broader parity theme | This gives the next execution slice a hard completion metric and the shortest path to improving the reference comparison story. |
| Treat harness-canonicalization fixes and implementation fixes as part of the same plan | The user-facing parity result depends on both, and the current mismatch set may include both categories. |
| Update docs only after the mismatch run is rerun | The comparison docs should report the measured post-fix state, not just the intended direction. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
