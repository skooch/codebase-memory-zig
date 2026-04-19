# Plan: Route And Cross Service Framework Depth

## Goal
Broaden the route and cross-service framework contract beyond the currently verified slices without regressing the existing route, event-topic, and message-flow fixtures.

## Current Phase
Completed

## File Map
- Archive: `docs/plans/implemented/05-route-and-cross-service-framework-depth-plan.md`
- Archive: `docs/plans/implemented/05-route-and-cross-service-framework-depth-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`

## Phases

### Phase 1: Choose the next bounded framework tranche
- [x] Inventory the already-green route and event-topic slices and choose the next concrete framework or broker patterns to promote.
- [x] Probe the candidate patterns in both implementations before promising them in the public harness.
- [x] Write the selected framework signatures, edge expectations, and explicit non-goals into `docs/plans/implemented/05-route-and-cross-service-framework-depth-progress.md`.
- **Status:** completed

### Phase 2: Implement the next route and broker slice
- [x] Promote the selected shared framework slice only where the current implementation and harness already prove stable overlap.
- [x] Leave non-overlapping framework fixtures explicitly documented as non-goals for this pass instead of widening the public contract prematurely.
- [x] Keep the affected fixtures, manifest assertions, and goldens unchanged because the selected shared tranche was already green in zig-only and full-compare runs.
- **Status:** completed

### Phase 3: Rebaseline framework-depth claims
- [x] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the route and cross-service rows reflect the new measured coverage depth.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the new tranche is proven end to end.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep each pass to one coherent framework tranche | The route and broker surface is too broad to advance safely in one jump. |
| Preserve existing fixtures as non-regression gates | The current route graph contract is already strong and should not drift. |
| Promote only overlap that survives full compare | The docs already distinguish shared parity from Zig-only expansion. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
