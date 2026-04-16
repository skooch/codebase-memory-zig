# Plan: Graph Enrichment Parity

## Status
In progress as of 2026-04-16. This plan was resumed from the former paused
graph-enrichment plan after the graph-model parity plan completed.

The old bundled scope is no longer accurate as-is: git-history coupling,
route/config fixture parity, route-linked data flow, async route callers, and
route summaries are already implemented for the verified graph-model fixture
contract. This resumed plan now acts as the coordination entrypoint for optional
graph-enrichment expansion beyond that verified contract.

## Goal
Promote only the remaining graph-enrichment work that still improves parity with
the original project after graph-model parity: broader route/cross-service
framework coverage first, then broader config normalization and edge-expansion
coverage where the C reference can prove an overlapping contract.

## Current Phase
Phase 1: reconciled and ready to start the route follow-on first.

## File Map
- Modify: `docs/plans/in-progress/ready-to-go/04-graph-enrichment-parity-plan.md`
- Create/modify:
  `docs/plans/in-progress/ready-to-go/04-graph-enrichment-parity-progress.md`
- Coordinate:
  `docs/plans/in-progress/follow-ons/route-graph-parity-plan.md`
- Coordinate:
  `docs/plans/in-progress/follow-ons/config-linking-and-edge-expansion-plan.md`
- Later status updates may touch:
  `docs/port-comparison.md`, `docs/gap-analysis.md`, `docs/zig-port-plan.md`

## Phases

### Phase 1: Reconcile Resumed Scope
- [x] Move the paused enrichment, route, and config plans back under
  `docs/plans/in-progress/`.
- [x] Remove superseded “start from zero” language from the active plans.
- [x] Record that graph-model parity itself is complete at
  `docs/plans/implemented/graph-model-parity-plan.md`.
- [x] Choose the first child plan to execute.
- **Status:** complete

### Phase 2: Execute Route Follow-On First
- [ ] Run the route graph follow-on plan through fixture design, C/Zig probing,
  implementation, and verification.
- [ ] Keep strict shared assertions limited to rows the C reference exposes.
- [ ] Keep Zig-only tests for useful route behavior that the C reference does not
  expose through the public harness.
- **Status:** next

### Phase 3: Execute Config / Edge Follow-On Second
- [ ] Re-probe config and long-tail edge candidates after route work lands.
- [ ] Promote only proven shared rows into strict interop assertions.
- [ ] Leave unproven or C-empty rows as documented future work instead of parity
  claims.
- **Status:** queued

### Phase 4: Reclassify Docs
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and
  `docs/zig-port-plan.md` only after each child plan has green verification.
- [ ] Move completed child plans to `docs/plans/implemented/` after required
  verification passes.
- **Status:** pending

## Recommendation
Start with `docs/plans/in-progress/follow-ons/route-graph-parity-plan.md`.
Route expansion is the highest-leverage first step because the existing Zig
substrate already has route nodes, `HTTP_CALLS`, `ASYNC_CALLS`, `HANDLES`,
route-linked `DATA_FLOWS`, and route summaries. Broader route fixtures are also
more visible in `get_architecture`, `trace_call_path`, and `query_graph` than
additional config-key normalization, so they give faster parity signal.

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this plan as an umbrella | The completed graph-model plan already did the core implementation; the remaining work is sequencing and status integrity across route/config follow-ons. |
| Start with route expansion | It exercises the most user-visible graph surfaces and builds on existing route substrate rather than opening a new subsystem first. |
| Run config expansion second | Config matching is valuable but easier to overclaim because the C reference often returns empty rows for candidate fixtures. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
