# Plan: Long-Tail Edge Parity

## Goal
Expand the Zig graph's edge vocabulary beyond the already verified shared slice so the model breadth feels closer to the original when users inspect or market the system as a drop-in replacement.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/05-long-tail-edge-parity-plan.md`
- Create: `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/store.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/edge-parity/`

## Phases

### Phase 1: Lock the Edge-Breadth Contract
- [ ] Re-read the original long-tail edge families and capture the overlapping post-shared-slice edge expectations in `docs/gap-analysis.md`.
- [ ] Define the exact fixture queries and edge assertions in `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`.
- [ ] Add local parity fixtures under `testdata/interop/edge-parity/` that exercise the targeted long-tail edge families without depending on unrelated language-coverage work.
- **Status:** pending

### Phase 2: Implement Additional Edge Families
- [ ] Extend `src/extractor.zig`, `src/pipeline.zig`, `src/graph_buffer.zig`, and `src/store.zig` so the Zig graph can emit and persist the targeted long-tail edge families.
- [ ] Add focused regression coverage in `src/store_test.zig` so the new edge families stay queryable and stable once added.
- [ ] Expand `testdata/interop/manifest.json` so the shared edge assertions are locked into the existing parity harness.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and the edge-focused interop fixture checks until the targeted long-tail edge families are stable.
- [ ] Update `docs/port-comparison.md` so the long-tail edge row moves out of `Partial` only after the accepted overlap is verified.
- [ ] Record the final verification transcript and any intentionally unsupported edge families in `docs/plans/new/ready-to-go/05-long-tail-edge-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep edge-breadth separate from language expansion | Users care whether the graph model is broad even before every original language is supported, so edge breadth should have its own proof path. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
