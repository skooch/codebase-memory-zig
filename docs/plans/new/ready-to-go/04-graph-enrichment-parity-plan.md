# Plan: Graph Enrichment Parity

## Goal
Close the most visible graph-model gaps after tracing by adding the shared route, config-link, and git-history-derived enrichment layers that make the original feel broader than the current Zig graph.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/04-graph-enrichment-parity-plan.md`
- Create: `docs/plans/new/ready-to-go/04-graph-enrichment-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/discover.zig`
- Modify: `src/mcp.zig`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/graph-enrichment/`

## Phases

### Phase 1: Lock the Enrichment Contract
- [ ] Re-read the original route-node, config-link, and git-history-derived enrichment behavior and capture the overlapping graph expectations in `docs/gap-analysis.md`.
- [ ] Define the shared route, config-link, and git-history verification workflow in `docs/plans/new/ready-to-go/04-graph-enrichment-parity-progress.md`.
- [ ] Add local fixtures under `testdata/interop/graph-enrichment/` so enrichment behavior can be tested end to end without relying on a live external repository.
- **Status:** pending

### Phase 2: Implement Shared Enrichment Layers
- [ ] Extend `src/discover.zig`, `src/pipeline.zig`, `src/graph_buffer.zig`, and `src/store.zig` so the Zig graph can persist the overlapping route, config-link, and git-history-derived facts.
- [ ] Extend `src/mcp.zig` so the shared enrichment facts are exposed through the existing query and search surfaces rather than remaining internal-only.
- [ ] Add regression coverage and fixture-driven interop checks that lock the supported overlap for route nodes, config linking, and git-history coupling.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and the enrichment interop fixture checks until the shared route, config-link, and git-history rows are stable.
- [ ] Update `docs/port-comparison.md` so the graph-enrichment rows move out of `Deferred` only after the shared overlap is green.
- [ ] Record the final verification transcript and any intentionally unsupported enrichment cases in `docs/plans/new/ready-to-go/04-graph-enrichment-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Bundle the enrichment follow-ons together | For drop-in replacement positioning, route, config-link, and git-history gaps are easier to explain and verify as one graph-breadth upgrade than as three disconnected slices. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
