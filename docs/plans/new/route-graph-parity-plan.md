# Plan: Route Graph Parity

## Goal
Implement the original route and cross-service graph layer so the Zig port can model `Route`, `HTTP_CALLS`, `ASYNC_CALLS`, and related handler relationships.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/route-graph-parity-plan.md`
- Create: `docs/plans/new/route-graph-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/routes.zig`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/mcp.zig`
- Create: `testdata/interop/routes/express_app.js`
- Create: `testdata/interop/routes/worker.py`

## Phases

### Phase 1: Lock the Route Contract
- [ ] Re-read the original route-node and cross-service passes and capture the overlapping route graph contract in `docs/gap-analysis.md`.
- [ ] Add local JavaScript and Python route fixtures in `testdata/interop/routes/` so route extraction can be verified without external services.
- [ ] Record the expected node and edge queries plus verification commands in `docs/plans/new/route-graph-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement Route Graph Extraction
- [ ] Add `src/routes.zig` to own route discovery, handler association, and outbound edge extraction instead of overloading the general extractor.
- [ ] Extend `src/extractor.zig`, `src/pipeline.zig`, `src/store.zig`, `src/cypher.zig`, and `src/mcp.zig` so route nodes and route-linked edges are stored and queryable.
- [ ] Add focused regression coverage for handler resolution, duplicate route suppression, and supported framework heuristics.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and route-graph fixture queries until the supported route rows are stable.
- [ ] Update `docs/port-comparison.md` so the route-graph rows move out of `Deferred` only after the local fixtures prove them.
- [ ] Record supported frameworks and deferred framework gaps in `docs/plans/new/route-graph-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start with route fixtures that stay inside parser-backed languages | That keeps the first route tranche aligned with the current strongest extraction lanes. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
