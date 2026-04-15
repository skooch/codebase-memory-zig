# Plan: Semantic Graph Expansion Feature Cluster

## Status
Backlog improvement cluster. For the current original-project graph-model parity
work, use `docs/plans/new/graph-model-parity-plan.md`; this plan remains as
the broader upstream feature-pressure inventory for later semantic expansion.

## Goal
Sequence the upstream pressure for richer graph semantics into a substrate-first Zig roadmap that grows route, protocol, trace, and higher-order analysis features only after the underlying graph facts are stable.

## Research Basis

Upstream requests and gaps captured in this plan:
- Dynamic or indirect call surfaces: `#29`, `#55`, `#56`
- Higher-order graph analysis quality: `#57`, `#179`
- Existing deferred Zig rows that align with the upstream demand: routes, config-linking, richer trace breadth, and decorator enrichment

Upstream PRs that show the likely implementation shape:
- Event and async graph expansion: `#25`
- Graph and response-level analysis additions: `#61`, `#147`, `#148`, `#149`, `#151`
- Large semantic expansion bundles: `#162`, `#225`
- Focused semantic edge follow-on: `#208`
- Ecosystem graph additions adjacent to this work: `#87`

Observed upstream pattern:
- The ambitious feature PRs were attractive but often too wide, mixing new graph facts, new query tools, and new UX behaviors in one change.
- The upstream work that looked most durable added one new edge family or one new semantic domain at a time, then proved it on real fixtures before layering new analysis tools on top.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md`
- Create: `docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/pipeline.zig`
- Modify: `src/query_router.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/mcp.zig`
- Create: `src/routes.zig`
- Create: `src/semantic_links.zig`
- Create: `docs/graph-expansion-roadmap.md`
- Create: `testdata/interop/semantic-expansion/http_routes/index.ts`
- Create: `testdata/interop/semantic-expansion/pubsub_events/main.py`

## Phases

### Phase 1: Lock the Expansion Order
- [ ] Map the upstream semantic requests into a strict dependency order in `docs/gap-analysis.md`: route facts, async/protocol facts, richer trace views, and only then higher-order analytics such as communities or blast-radius summaries.
- [ ] Add route and pub-sub fixtures under `testdata/interop/semantic-expansion/` so new edge families can be verified without external services.
- [ ] Record the first semantic tranche, deferred analysis surfaces, and exact verification commands in `docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-progress.md`.
- **Status:** pending

### Phase 2: Land One Semantic Substrate at a Time
- [ ] Add `src/routes.zig` and `src/semantic_links.zig` so route extraction and protocol or indirect-call linking can evolve as explicit subsystems instead of spreading special cases across the generic extractor.
- [ ] Extend `src/pipeline.zig`, `src/store.zig`, `src/cypher.zig`, `src/query_router.zig`, and `src/mcp.zig` so new node and edge families are stored and queryable before adding any compound analysis helpers.
- [ ] Keep higher-order features like community summaries, blast radius, and compound query helpers documented as follow-ons until the supporting facts are fixture-backed.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and fixture-level route and async edge queries until the first semantic tranche is stable.
- [ ] Update `docs/graph-expansion-roadmap.md` and `docs/port-comparison.md` only for the semantic surfaces that now have verified graph facts underneath them.
- [ ] Record still-deferred analysis features and their prerequisites in `docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Build new graph facts before new graph summaries | The upstream PR history shows that summary tools become noisy or misleading when the underlying edge families are incomplete. |
| Split route and protocol work into dedicated modules | Those features kept reappearing upstream and are easier to verify when they are not hidden inside general extraction code. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
