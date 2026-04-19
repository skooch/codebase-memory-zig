# Plan: Route And Cross-Service Framework Expansion

## Goal
Broaden the verified route and cross-service semantic contract beyond the current bounded fixtures so the Zig port covers more real framework registration and message-flow patterns without regressing the already-green route and event-topic slices.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/04-route-and-cross-service-framework-expansion-plan.md`
- Create: `docs/plans/new/04-route-and-cross-service-framework-expansion-progress.md`
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
- Modify: `testdata/interop/golden/graph-model-routes.json`
- Modify: `testdata/interop/golden/graph-model-async.json`
- Modify: `testdata/interop/golden/route-expansion-httpx.json`
- Create: `testdata/interop/route-expansion/`
- Create: `testdata/interop/semantic-expansion/`

## Phases

### Phase 1: Choose the next framework-expansion tranche
- [ ] Review the currently implemented route and event-topic fixture surface and select the next bounded framework or broker patterns that matter most for parity, using the existing route and semantic-expansion fixtures as the baseline.
- [ ] Define the exact framework signatures, handler attribution rules, and route/topic edge expectations for the tranche in `docs/plans/in-progress/04-route-and-cross-service-framework-expansion-progress.md` before code changes begin.
- [ ] Confirm which of those patterns belong in `src/extractor.zig`, which belong in `src/routes.zig`, which belong in `src/semantic_links.zig`, and which require query-surface updates in `src/query_router.zig`.
- **Status:** pending

### Phase 2: Implement the next route and message-flow slice
- [ ] Extend `src/extractor.zig` and `src/pipeline.zig` so the chosen framework registrations and handler ownership facts are captured without broadening false positives.
- [ ] Extend `src/routes.zig` and `src/semantic_links.zig` so the chosen HTTP and async framework patterns emit the correct `Route`, `HANDLES`, `HTTP_CALLS`, `ASYNC_CALLS`, `EMITS`, `SUBSCRIBES`, or `DATA_FLOWS` edges.
- [ ] Add fixture-backed regression coverage in `testdata/interop/route-expansion/`, `testdata/interop/semantic-expansion/`, `src/query_router_test.zig`, and `src/store_test.zig` for the newly supported route and cross-service patterns.
- **Status:** pending

### Phase 3: Rebaseline parity evidence and docs
- [ ] Refresh the affected interop manifest entries and goldens only after the new framework tranche is verified in zig-only and full-compare runs.
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`, and record whether the broader route/cross-service gap in `docs/port-comparison.md` narrowed materially.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the remaining route and cross-service expansion debt is described from the new baseline rather than the current one.
- [ ] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the added framework tranche is verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this as a bounded framework tranche instead of “all routes everywhere” | The route and message-flow surface is too broad for one safe slice; the plan should add one coherent verified expansion at a time. |
| Protect existing route and event-topic fixtures as non-regression gates | The current route contract is already green and should stay stable while expansion continues. |
| Favor fixture-backed framework support over generic heuristics | The parser-accuracy work already showed that broad heuristics create false route signals. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
