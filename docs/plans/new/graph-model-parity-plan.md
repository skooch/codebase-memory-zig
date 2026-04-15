# Plan: Graph Model Parity

## Goal
Close the remaining graph-model gaps that still prevent the Zig port from making
a feature-parity claim against the original project: route handler modeling,
route-linked data flow, decorator route detection, and the broader config-link
normalization surface.

## Current Phase
Awaiting approval to execute. Move this plan to `docs/plans/in-progress/`
before implementation starts.

## Current Codebase State
- Complete and verified: advanced trace modes, risk labels, include-tests
  filtering, git-history `FILE_CHANGES_WITH`, test tagging, shared
  `CONFIGURES` / `USES_TYPE`, and long-tail `THROWS` / `RAISES` edge parity.
- Partial and reusable: `src/service_patterns.zig` classifies service calls,
  `src/route_nodes.zig` creates deterministic `Route` nodes from `HTTP_CALLS`
  and `ASYNC_CALLS`, `src/pipeline.zig` emits service-pattern call edges, and
  `src/query_router.zig` can expose route summaries.
- Still missing for graph-model parity: route handler association, `HANDLES`
  edges, route-linked `DATA_FLOWS`, decorator/framework route extraction, and
  the full config normalization/linking surface beyond the current key-symbol
  and dependency-import strategies.
- Current full Zig-vs-C harness baseline after plan reconciliation:
  `151` comparisons, `86` strict matches, `19` diagnostic-only comparisons,
  `10` mismatches. The graph-model-related mismatches include the existing
  `graph-enrichment-config-deps` and `graph-enrichment-http-calls` query rows.

## Superseded Plans
- `docs/plans/paused/ready-to-go/04-graph-enrichment-parity-plan.md`
- `docs/plans/paused/superseded/route-graph-parity-plan.md`
- `docs/plans/paused/superseded/config-linking-and-edge-expansion-plan.md`

## File Map
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/service_patterns.zig`
- Modify: `src/route_nodes.zig`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/query_router.zig`
- Modify: `src/mcp.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/graph-model/routes/`
- Create: `testdata/interop/graph-model/config/`
- Create: `docs/plans/in-progress/graph-model-parity-progress.md` after approval

## Phases

### Phase 1: Lock the Remaining Graph Contract
- [ ] Re-read the original route, config-linking, and semantic-edge passes and record only the overlapping behavior still missing from the Zig port.
- [ ] Define fixture-backed acceptance rules for `Route`, `HANDLES`, `HTTP_CALLS`, `ASYNC_CALLS`, route-linked `DATA_FLOWS`, decorator route extraction, and config normalization/linking.
- [ ] Add minimal JavaScript/TypeScript and Python fixtures under `testdata/interop/graph-model/` before changing extractor behavior.
- **Status:** pending approval

### Phase 2: Complete Route Handler Modeling
- [ ] Extend route extraction so supported framework registrations and decorators resolve to handler symbols instead of only creating route rendezvous nodes from outbound calls.
- [ ] Emit `HANDLES` edges from handler functions/methods to `Route` nodes, preserving method/path metadata and duplicate-route suppression.
- [ ] Add store, extractor, pipeline, and Cypher regression coverage for route node creation, handler association, and route summary exposure.
- **Status:** pending approval

### Phase 3: Add Route-Linked Data Flow
- [ ] Define the first accepted `DATA_FLOWS` route-link contract from request entry points through handler calls without pretending to solve full local data-flow analysis.
- [ ] Persist route-linked `DATA_FLOWS` edges and make `trace_call_path` / `query_graph` able to traverse them through the existing edge-type filtering paths.
- [ ] Add interop assertions that prove data-flow edges are present only when supported route facts exist underneath them.
- **Status:** pending approval

### Phase 4: Finish Config-Link Normalization
- [ ] Extend config-key extraction and matching only for original-overlap config patterns with fixture evidence.
- [ ] Preserve raw config keys while adding the minimum normalized lookup metadata needed for stable links.
- [ ] Add regression coverage for config-key normalization, dependency-import matching, deduplication, and query visibility.
- **Status:** pending approval

### Phase 5: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and focused graph-model fixture queries.
- [ ] Run the full Zig-vs-C interop harness if the C reference binary is available locally.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` only for rows backed by the new fixtures.
- [ ] Move this plan and its progress log to `docs/plans/implemented/` only after all required verification passes.
- **Status:** pending approval

## Decisions
| Decision | Rationale |
|----------|-----------|
| One graph-model plan replaces three narrower pending plans | Route, config, and semantic-edge parity share extractor, pipeline, store, Cypher, and interop surfaces; a single dependency order avoids contradictory partial claims. |
| Build graph facts before summaries | Architecture and trace outputs become credible only after route/config/data-flow facts are persisted and queryable. |
| Keep full local data-flow out of the first route tranche | The original-overlap parity gap is route-linked flow, not a general-purpose data-flow engine. |
| Preserve raw config keys | The algorithm audit warns against over-normalizing config keys; normalization should be explicit metadata, not a destructive rewrite. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
