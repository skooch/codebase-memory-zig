# Plan: Semantic Graph Expansion Feature Cluster

## Status
Complete. The original-project graph-model parity plan is complete at
`docs/plans/implemented/graph-model-parity-plan.md`; this plan closed the
remaining bounded semantic-expansion tranche for explicit route helpers,
pub-sub topic links, and architecture or trace visibility.

## Goal
Sequence the upstream pressure for richer graph semantics into a substrate-first Zig roadmap that grows route, protocol, trace, and higher-order analysis features only after the underlying graph facts are stable.

## Research Basis

Upstream requests and gaps captured in this plan:
- Dynamic or indirect call surfaces: `#29`, `#55`, `#56`
- Higher-order graph analysis quality: `#57`, `#179`
- Existing Zig rows that align with the upstream demand: optional route/config expansion beyond the verified graph-model fixture contract, richer trace-derived analysis views, and decorator enrichment

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
Phase 3

## File Map
- Modify: `docs/plans/implemented/semantic-graph-expansion-feature-cluster-plan.md`
- Create: `docs/plans/implemented/semantic-graph-expansion-feature-cluster-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/pipeline.zig`
- Modify: `src/query_router.zig`
- Modify: `src/extractor.zig`
- Modify: `src/mcp.zig`
- Modify: `src/root.zig`
- Create: `src/routes.zig`
- Create: `src/semantic_links.zig`
- Create: `docs/graph-expansion-roadmap.md`
- Create: `testdata/interop/semantic-expansion/http_routes/index.ts`
- Create: `testdata/interop/semantic-expansion/pubsub_events/main.py`
- Modify: `src/query_router_test.zig`

## Phases

### Phase 1: Lock the Expansion Order
- [x] Map the upstream semantic requests into a strict dependency order in `docs/gap-analysis.md`: route facts, async/protocol facts, richer trace views, and only then higher-order analytics such as communities or blast-radius summaries.
- [x] Add route and pub-sub fixtures under `testdata/interop/semantic-expansion/` so new edge families can be verified without external services.
- [x] Record the first semantic tranche, deferred analysis surfaces, and exact verification commands in `docs/plans/implemented/semantic-graph-expansion-feature-cluster-progress.md`.
- **Status:** complete

### Phase 2: Land One Semantic Substrate at a Time
- [x] Add `src/routes.zig` and `src/semantic_links.zig` so route extraction and protocol or indirect-call linking can evolve as explicit subsystems instead of spreading special cases across the generic extractor.
- [x] Extend `src/pipeline.zig`, `src/extractor.zig`, `src/query_router.zig`, and `src/mcp.zig` so new node and edge families are synthesized, summarized, and traceable before adding any compound analysis helpers.
- [x] Keep higher-order features like community summaries, blast radius, and compound query helpers documented as follow-ons until the supporting facts are fixture-backed.
- **Status:** complete

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and fixture-level route and async edge queries until the first semantic tranche is stable.
- [x] Update `docs/graph-expansion-roadmap.md` and `docs/port-comparison.md` only for the semantic surfaces that now have verified graph facts underneath them.
- [x] Record still-deferred analysis features and their prerequisites in `docs/plans/implemented/semantic-graph-expansion-feature-cluster-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Build new graph facts before new graph summaries | The upstream PR history shows that summary tools become noisy or misleading when the underlying edge families are incomplete. |
| Split route and protocol work into dedicated modules | Those features kept reappearing upstream and are easier to verify when they are not hidden inside general extraction code. |
| Close this plan with a bounded first tranche instead of a full graph rewrite | The repo already has route facts and generic edge storage, so the durable next step is explicit helpers plus one verified event-link family rather than a speculative analytics bundle. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `scripts/fetch_grammars.sh` skipped missing PowerShell and GDScript vendored grammars because it only checked `rust/parser.c` | `zig build test` failed after worktree bootstrap with missing `vendored/grammars/powershell/parser.c`, and a plain `bash scripts/fetch_grammars.sh` incorrectly reported success | Updated the fetch script to verify every required vendored grammar before early exit, documented the failure mode in `CLAUDE.md`, and reran the fetch before final verification |
