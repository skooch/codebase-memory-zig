# Plan: Graph Model Parity

## Goal
Close the remaining graph-model gaps that still prevent the Zig port from making
a feature-parity claim against the original project: route handler modeling,
route-linked data flow, decorator route detection, and the broader config-link
normalization surface.

## Current Phase
Phase 2 route handler modeling is in progress. The first slice has landed:
decorator route extraction now creates `Route` nodes and `HANDLES` edges, and
route-registration calls preserve enough call metadata to emit `HANDLES` when
the handler reference resolves.

## Current Codebase State
- Complete and verified: advanced trace modes, risk labels, include-tests
  filtering, git-history `FILE_CHANGES_WITH`, test tagging, shared
  `CONFIGURES` / `USES_TYPE`, and long-tail `THROWS` / `RAISES` edge parity.
- Partial and reusable: `src/service_patterns.zig` classifies service calls,
  `src/route_nodes.zig` creates deterministic `Route` nodes from `HTTP_CALLS`
  and `ASYNC_CALLS`, `src/pipeline.zig` emits service-pattern call edges, and
  `src/query_router.zig` can expose route summaries.
- Newly implemented in this session: Python decorator route extraction emits
  `Route` nodes and `HANDLES` edges; framework route-registration calls such as
  `app.get("/path", handler)` now carry route metadata and emit `Route`,
  `CALLS`, and `HANDLES` facts when the handler resolves.
- Still missing for graph-model parity: route-linked `DATA_FLOWS`, broader
  framework route coverage, HTTP/async calls routed through concrete URL route
  nodes, and the full config normalization/linking surface beyond the current
  key-symbol and dependency-import strategies.
- Current full Zig-vs-C harness baseline after this route slice:
  `158` comparisons, `89` strict matches, `20` diagnostic-only comparisons,
  `10` mismatches, and `cli_progress: match`. The graph-model-related
  mismatches still include the existing `graph-enrichment-config-deps` and
  `graph-enrichment-http-calls` query rows.

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
- [x] Re-read the original route, config-linking, and semantic-edge passes and record only the overlapping behavior still missing from the Zig port.
- [x] Define fixture-backed acceptance rules for decorator-backed `Route` and `HANDLES` facts.
- [ ] Define fixture-backed acceptance rules for `HTTP_CALLS`, `ASYNC_CALLS`, route-linked `DATA_FLOWS`, and config normalization/linking.
- [x] Add a minimal Python route fixture under `testdata/interop/graph-model/routes/`.
- [ ] Add minimal JavaScript/TypeScript route fixtures once the shared C/Zig public behavior is established for those registrations.
- **Status:** partially complete

### Phase 2: Complete Route Handler Modeling
- [x] Extend Python decorator route extraction so handlers create route rendezvous nodes.
- [x] Preserve route-registration call metadata and emit `HANDLES` when handler references resolve.
- [x] Emit `HANDLES` edges from handler functions/methods to `Route` nodes for the first supported decorator and registration slices.
- [x] Add extractor, pipeline, and interop regression coverage for route node creation and handler association.
- [ ] Broaden framework coverage and add route summary exposure coverage.
- **Status:** in progress

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
- [x] Run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and focused graph-model fixture queries.
- [x] Run the full Zig-vs-C interop harness if the C reference binary is available locally.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` only for rows backed by the new fixtures.
- [ ] Move this plan and its progress log to `docs/plans/implemented/` only after all required verification passes.
- **Status:** in progress

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
