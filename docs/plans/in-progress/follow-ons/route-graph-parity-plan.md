# Plan: Route Graph Parity Follow-On

## Status
In progress as of 2026-04-16. This plan was resumed from the former
paused/superseded route plan and narrowed to the remaining route work after
`docs/plans/implemented/graph-model-parity-plan.md`.

Already complete for the verified graph-model fixture contract: Python
decorator-backed `Route` / `HANDLES`, concrete URL/path/topic `Route` nodes,
`HTTP_CALLS`, `ASYNC_CALLS`, strict shared route-linked `DATA_FLOWS`, and route
summary exposure.

## Goal
Expand route and cross-service graph coverage beyond the verified fixture
contract without weakening parity claims. The next tranche should prove broader
framework route registrations and route caller behavior through local fixtures,
then promote only C/Zig-overlapping rows into strict interop assertions.

## Current Phase
Phase 1 complete. The first accepted shared follow-on fixture is the Python
`httpx` caller variant with a local stub and filtered `fetch_users` queries.

## File Map
- Modify:
  `docs/plans/in-progress/follow-ons/route-graph-parity-plan.md`
- Create/modify:
  `docs/plans/in-progress/follow-ons/route-graph-parity-progress.md`
- Likely modify: `src/service_patterns.zig`
- Likely modify: `src/extractor.zig`
- Likely modify: `src/pipeline.zig`
- Likely modify: `src/route_nodes.zig`
- Likely modify: `src/query_router.zig`
- Likely modify: `testdata/interop/manifest.json`
- Likely create fixtures under `testdata/interop/route-expansion/`

## Phases

### Phase 1: Lock The Route Expansion Contract
- [x] Probe the current C reference and Zig implementation with small route
  fixture candidates before adding strict assertions.
- [x] Prefer parser-backed languages already strong in this port: Python and
  JavaScript were probed first; TypeScript can be treated as follow-on only if a
  concrete C-exposed route pattern appears worth testing.
- [x] Choose the first fixture set with positive shared overlap. The accepted
  first follow-on fixture is a Python `httpx` caller with a local `httpx.py`
  stub and filtered `fetch_users` queries; JavaScript route-registration and
  direct Python route-registration probes remain Zig-only.
- [x] Record accepted rows, rejected candidates, and exact verification commands
  in `docs/plans/in-progress/follow-ons/route-graph-parity-progress.md`.
- **Status:** complete

### Phase 2: Implement Missing Route Cases
- [ ] Extend current route substrate modules instead of adding a parallel
  `src/routes.zig` unless the implementation becomes too coupled:
  `src/service_patterns.zig`, `src/extractor.zig`, `src/pipeline.zig`, and
  `src/route_nodes.zig`.
- [x] Preserve existing graph-model fixtures while adding broader route
  registration and caller coverage through the new `route-expansion-httpx`
  fixture.
- [ ] Add focused regression coverage for route method inference, handler
  reference resolution, duplicate route suppression, and route summary output.
- **Status:** in progress

### Phase 3: Verify And Reclassify
- [ ] Run `zig fmt` on touched Zig files.
- [ ] Run `zig build test`.
- [ ] Run `zig build`.
- [ ] Run `bash scripts/run_interop_alignment.sh --zig-only`.
- [ ] Run `bash scripts/run_interop_alignment.sh` and confirm any new strict
  route assertions are green.
- [ ] Update `docs/port-comparison.md` / `docs/gap-analysis.md` only as far as
  the evidence supports.
- **Status:** pending

## Acceptance Rules
- A route row can become a strict interop assertion only after both current C and
  Zig binaries expose the same row shape on the same local fixture.
- Useful Zig behavior that the C reference does not expose must stay in unit or
  Zig-only fixture coverage, not in a shared parity claim.
- The plan is complete only after the full harness has no new route-related
  mismatches and the documentation records any intentionally unsupported
  frameworks.

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start route follow-on before config follow-on | Route facts are more visible through architecture summaries, traces, and Cypher queries, and the current Zig substrate is already close enough for small focused fixture expansion. |
| Reuse `src/route_nodes.zig` | The current code already owns route-node materialization and route-linked `DATA_FLOWS`; introducing `src/routes.zig` now would be a refactor, not a prerequisite. |
| Probe C before strict assertions | Previous route work showed plausible fixtures can diverge on method/QN shape, so strict rows must be evidence-led. |
| Reject empty-or-Zig-only route probes early | The first probe set already showed several useful Zig rows that the current C binary does not expose. These belong in Zig-only coverage unless shared overlap appears. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Initial `py-httpx` probe used a manifest project name that did not match the indexed directory basename, which made the Zig query rows appear empty while C returned rows. | Ran the first compare manifest with `project: "py-httpx"` against a directory named `py_httpx`. | Re-ran the probe with project names matching the indexed directory basenames before drawing parity conclusions. |
