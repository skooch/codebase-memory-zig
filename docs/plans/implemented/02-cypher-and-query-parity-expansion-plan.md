# Plan: Cypher And Query Parity Expansion

## Goal
Expand the read-only Cypher and query contract so the Zig port closes more of the remaining advanced `query_graph` parity gap beyond the currently fixed daily-use subset.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/02-cypher-and-query-parity-expansion-plan.md`
- Create: `docs/plans/new/02-cypher-and-query-parity-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/cypher.zig`
- Modify: `src/store.zig`
- Modify: `src/mcp.zig`
- Modify: `src/query_router.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/javascript-parity.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `testdata/interop/golden/java-basic.json`
- Modify: `testdata/interop/golden/python-parity.json`

## Phases

### Phase 1: Define the missing query surface
- [ ] Audit the current full-compare `query_graph` deltas and the `docs/port-comparison.md` “No full Cypher parity” claim to identify the exact read-only query forms still missing or divergent.
- [ ] Classify those gaps across `src/cypher.zig`, `src/store.zig`, and `src/query_router.zig` into parser gaps, planner or executor gaps, row-shape differences, and ordering differences.
- [ ] Write the prioritized query subset for this execution slice into `docs/plans/in-progress/02-cypher-and-query-parity-expansion-progress.md` before implementation starts.
- **Status:** pending

### Phase 2: Implement the next read-only query tranche
- [ ] Extend `src/cypher.zig` and `src/store.zig` to support the chosen missing query forms, filters, or ordering semantics without regressing the current passing daily-use subset.
- [ ] Update `src/mcp.zig` and `src/query_router.zig` only where payload shaping or error surfaces need to stay aligned with the expanded query executor behavior.
- [ ] Add focused regression coverage in `src/store_test.zig` and `src/mcp.zig` for each newly supported query form so future parity drift is caught before the interop harness.
- **Status:** pending

### Phase 3: Rebaseline parity evidence
- [ ] Update the affected interop fixture expectations and goldens in `testdata/interop/manifest.json` and `testdata/interop/golden/*.json` only after the expanded query forms are verified against the C reference.
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`, and record which query categories moved from mismatch to match or from undocumented to documented residual debt.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the “full Cypher parity” language reflects the post-slice state honestly.
- [ ] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the expanded query tranche is verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Limit the slice to read-only `query_graph` parity | The current product contract explicitly centers the read-only Cypher surface, so that is the highest-value remaining query work. |
| Use current fixture deltas to choose the next query forms | The full compare already identifies where parity is still weakest. |
| Keep docs updates in the same plan | Query parity is one of the top-level remaining differences the comparison docs call out directly. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
