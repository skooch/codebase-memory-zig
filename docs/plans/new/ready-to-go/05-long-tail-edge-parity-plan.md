# Plan: Long-Tail Edge Parity

## Goal
Expand the Zig graph's edge vocabulary beyond the already verified shared slice so the model breadth feels closer to the original when users inspect or market the system as a drop-in replacement.

## Current Phase
Phase 3 (verification)

## File Map
- Modify: `docs/plans/new/ready-to-go/05-long-tail-edge-parity-plan.md`
- Create: `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/edge-parity/`

## Phases

### Phase 1: Lock the Edge-Breadth Contract
- [x] Re-read the original long-tail edge families and capture the overlapping post-shared-slice edge expectations.
- [x] Define the exact fixture queries and edge assertions in `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`.
- [x] Add local parity fixtures under `testdata/interop/edge-parity/` that exercise the targeted long-tail edge families without depending on unrelated language-coverage work.
- **Status:** complete

### Phase 2: Implement Additional Edge Families
- [x] Extend `src/extractor.zig` and `src/pipeline.zig` so the Zig graph can emit and persist WRITES and THROWS/RAISES edge families.
- [x] Add focused regression coverage in `src/store_test.zig` so the new edge families stay queryable and stable once added.
- [x] Expand `testdata/interop/manifest.json` so the shared edge assertions are locked into the existing parity harness.
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] Run `zig build`, `zig build test`, and the edge-focused interop fixture checks until the targeted long-tail edge families are stable.
- [ ] Update `docs/port-comparison.md` so the long-tail edge row moves out of `Partial` only after the accepted overlap is verified.
- [ ] Update `docs/gap-analysis.md` with the new edge family status.
- [ ] Record the final verification transcript in `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`.
- **Status:** in progress

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep edge-breadth separate from language expansion | Users care whether the graph model is broad even before every original language is supported, so edge breadth should have its own proof path. |
| OVERRIDE out of scope | Go-only in the C implementation; Go is not a target language in the Zig port. |
| CONTAINS_PACKAGE out of scope | Never actually implemented in the C codebase (documented but no creation code exists). |
| HANDLES/DATA_FLOWS out of scope | Part of the deferred route-graph system, tracked separately. |
| READS out of scope | C implementation only extracts WRITES from assignments, not READS. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Manifest used `type(r)` function | Cypher engine doesn't support function calls beyond COUNT | Changed to `r.type` property access |
| WRITES returned 0 rows with local vars | Local variables not in registry | Updated fixture to use module-level variable |
