# Plan: Route And Cross Service Framework Depth

## Goal
Broaden the route and cross-service framework contract beyond the currently verified slices without regressing the existing route, event-topic, and message-flow fixtures.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/05-route-and-cross-service-framework-depth-plan.md`
- Create: `docs/plans/new/05-route-and-cross-service-framework-depth-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/routes.zig`
- Modify: `src/semantic_links.zig`
- Modify: `src/query_router.zig`
- Modify: `src/query_router_test.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/`
- Modify: `testdata/interop/route-expansion/`
- Modify: `testdata/interop/semantic-expansion/`

## Phases

### Phase 1: Choose the next bounded framework tranche
- [ ] Inventory the already-green route and event-topic slices and choose the next concrete framework or broker patterns to promote.
- [ ] Probe the candidate patterns in both implementations before promising them in the public harness.
- [ ] Write the selected framework signatures, edge expectations, and explicit non-goals into `docs/plans/in-progress/05-route-and-cross-service-framework-depth-progress.md`.
- **Status:** pending

### Phase 2: Implement the next route and broker slice
- [ ] Extend `src/extractor.zig`, `src/pipeline.zig`, `src/routes.zig`, and `src/semantic_links.zig` for the selected framework registrations or broker dispatch patterns.
- [ ] Add or tighten query-router and store regression coverage for the new route and cross-service facts.
- [ ] Refresh the affected fixtures, manifest assertions, and goldens only after the selected tranche passes zig-only and full-compare runs.
- **Status:** pending

### Phase 3: Rebaseline framework-depth claims
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the route and cross-service rows reflect the new measured coverage depth.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the new tranche is proven end to end.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep each pass to one coherent framework tranche | The route and broker surface is too broad to advance safely in one jump. |
| Preserve existing fixtures as non-regression gates | The current route graph contract is already strong and should not drift. |
| Promote only overlap that survives full compare | The docs already distinguish shared parity from Zig-only expansion. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
