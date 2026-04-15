# Plan: Graph Model Parity

## Goal
Close the remaining graph-model gaps that still prevent the Zig port from making
a feature-parity claim against the original project: route handler modeling,
route-linked data flow, decorator route detection, and the broader config-link
normalization surface.

## Current Phase
Phase 3 route-linked data flow is complete for the first shared public fixture,
and the first shared async route caller fixture is now locked:
decorator route extraction creates `Route` nodes and `HANDLES` edges,
route-registration calls preserve enough call metadata to emit `HANDLES` when
the handler reference resolves, and the shared Python route fixture now proves a
strict C/Zig `DATA_FLOWS` row through a `GET` route. The async fixture proves a
broker-specific `Route` and `ASYNC_CALLS` row for a local `celery.delay` topic.

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
- Newly implemented after the first route slice: Zig now emits concrete
  URL/path `Route` caller edges from supported HTTP service calls and resolved
  URL-argument calls, and bridges route callers to `HANDLES` targets with
  `DATA_FLOWS`. The `graph-model-routes` fixture now uses a method-specific
  `@app.get` handler plus a local `requests` stub so both C and Zig expose the
  strict `fetch_users -> list_users` `DATA_FLOWS` row.
- Newly implemented for async route coverage: Zig accepts async broker topics,
  preserves broker names for route QNs/properties, and the `graph-model-async`
  fixture proves the shared `enqueue_users -> users.refresh` `ASYNC_CALLS` row.
- Still missing for graph-model parity: broader framework route coverage and
  the full config normalization/linking surface beyond the current key-symbol
  and dependency-import strategies.
- Current full Zig-vs-C harness baseline after this route slice:
  `165` comparisons, `92` strict matches, `21` diagnostic-only comparisons,
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
- [x] Define fixture-backed acceptance rules for first-slice `HTTP_CALLS` route callers and route-linked `DATA_FLOWS` in Zig.
- [x] Define fixture-backed acceptance rules for strict shared C/Zig `DATA_FLOWS`.
- [x] Define fixture-backed acceptance rules for strict shared C/Zig `ASYNC_CALLS`.
- [ ] Define fixture-backed acceptance rules for config normalization/linking.
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
- [x] Define the first accepted `DATA_FLOWS` route-link contract from route caller edges through `HANDLES` targets without pretending to solve full local data-flow analysis.
- [x] Persist route-linked `DATA_FLOWS` edges and make `query_graph` able to traverse them through the existing edge-type filtering paths.
- [x] Add regression coverage that proves data-flow edges are present only when supported route facts exist underneath them.
- [x] Find or construct a strict shared C/Zig public fixture for `DATA_FLOWS`.
- **Status:** complete for the first route-linked data-flow slice

### Phase 3b: Add Async Route Caller Coverage
- [x] Preserve async broker names when service-pattern calls emit topic route nodes.
- [x] Accept non-URL async topics such as `users.refresh` as route rendezvous targets.
- [x] Add a strict shared C/Zig fixture for `ASYNC_CALLS`.
- **Status:** complete for the first async route caller slice

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
