# Plan: Go Parity Query Graph Resolution

## Goal
Close the single remaining hard full-compare mismatch on `go-parity/query_graph` by making the Zig and C-visible query result contract agree on the exercised Go method-ownership case.

## Current Phase
Completed

## File Map
- Create: `docs/plans/new/01-go-parity-query-graph-resolution-plan.md`
- Create: `docs/plans/new/01-go-parity-query-graph-resolution-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `src/query_router_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `testdata/interop/language-expansion/go-basic/`
- Modify: `testdata/interop/go-parity/`

## Phases

### Phase 1: Reproduce and pin the Go query residual
- [x] Re-run the `go-parity` fixture in both zig-only and full-compare modes and capture the exact row-shape delta around `Class -> DEFINES_METHOD -> Method`.
- [x] Trace the Go extractor and pipeline ownership path that decides whether the receiver-owned method row is persisted for the queried fixture.
- [x] Record the exact expected post-fix query rows in `docs/plans/in-progress/01-go-parity-query-graph-resolution-progress.md` before changing extraction behavior.
- **Status:** completed

### Phase 2: Align Go ownership facts and fixture expectations
- [x] Adjust `src/extractor.zig` and `src/pipeline.zig` so the exercised Go receiver and method ownership facts produce the intended shared query result without regressing `go-basic`.
- [x] Add or tighten regression coverage in `src/store_test.zig` and `src/query_router_test.zig` for the exercised Go method-ownership rows.
- [x] Refresh the `go-parity` manifest assertion and golden snapshot only after the full compare shows the hard mismatch is gone.
- **Status:** completed

### Phase 3: Rebaseline parity docs
- [x] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` to remove or restate the Go residual from the new measured state.
- [x] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the mismatch is either resolved or reclassified with fresh evidence.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan tightly scoped to the single hard Go residual | The value is closing the only remaining hard mismatch, not reopening general language expansion. |
| Treat `go-basic` as a non-regression gate | The fix must not trade one Go fixture for another. |
| Update docs only from measured compare output | This plan exists to change the real mismatch count, not to soften wording around it. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
