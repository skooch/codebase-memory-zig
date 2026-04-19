# Plan: Full Cypher Query Parity Depth

## Goal
Broaden read-only Cypher parity beyond the currently verified floor so the comparison docs can claim a deeper query contract with fresh interop evidence.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/03-full-cypher-query-parity-depth-plan.md`
- Create: `docs/plans/new/03-full-cypher-query-parity-depth-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `src/cypher.zig`
- Modify: `src/query_router.zig`
- Modify: `src/mcp.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/`
- Create: `testdata/interop/cypher-expansion/`

## Phases

### Phase 1: Choose the next query-contract tranche
- [ ] Inventory the currently verified Cypher floor and select the next concrete query shapes to promote, such as multi-hop patterns, richer aggregates, ordering edge cases, or additional predicate forms.
- [ ] Confirm which of those candidate shapes already overlap between Zig and C on small direct probes before promoting them into the public harness.
- [ ] Record the exact next query tranche and affected fixture files in `docs/plans/in-progress/03-full-cypher-query-parity-depth-progress.md`.
- **Status:** pending

### Phase 2: Implement and verify the next query slice
- [ ] Extend `src/cypher.zig`, `src/query_router.zig`, and any needed MCP plumbing so the selected read-only query patterns work end to end.
- [ ] Add fixture-backed coverage under `testdata/interop/cypher-expansion/` and corresponding manifest assertions for the promoted query forms.
- [ ] Refresh only the affected goldens after the new query slice passes both zig-only and full-compare runs.
- **Status:** pending

### Phase 3: Rebaseline the query-parity claim
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so “no exhaustive Cypher parity” is restated from the new measured floor.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the broadened query floor is proven with harness evidence.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan read-only and Cypher-scoped | The docs currently distinguish query-floor depth from extraction fidelity. |
| Promote only query forms with direct overlap evidence | This avoids inflating the public contract with Zig-only semantics. |
| Prefer one coherent fixture tranche over many tiny unconnected assertions | Query parity is easier to maintain when the new floor is legible. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
