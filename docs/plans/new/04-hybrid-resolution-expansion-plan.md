# Plan: Hybrid Resolution Expansion

## Goal
Expand hybrid-resolution support beyond the bounded Go sidecar slice while keeping the public contract evidence explicit and non-regressive.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/04-hybrid-resolution-expansion-plan.md`
- Create: `docs/plans/new/04-hybrid-resolution-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/hybrid_resolution.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/registry.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/`
- Modify: `testdata/interop/hybrid-resolution/`

## Phases

### Phase 1: Define the next hybrid-resolution target
- [ ] Review the current bounded Go sidecar slice and choose the next concrete resolution target, such as additional Go ambiguity shapes or one explicit C/C++ sidecar-backed micro-case.
- [ ] Probe whether the candidate target can be expressed as a stable fixture contract without requiring a live external resolver.
- [ ] Write the exact supported target and non-goals into `docs/plans/in-progress/04-hybrid-resolution-expansion-progress.md`.
- **Status:** pending

### Phase 2: Extend sidecar-backed resolution
- [ ] Extend `src/hybrid_resolution.zig`, `src/pipeline.zig`, and `src/registry.zig` so the selected ambiguity case is resolved from explicit sidecar facts ahead of heuristic fallback.
- [ ] Add or extend fixture coverage under `testdata/interop/hybrid-resolution/` plus store-level regression coverage.
- [ ] Refresh the affected manifest assertions and goldens only after the selected slice is green in zig-only and full-compare runs.
- **Status:** pending

### Phase 3: Rebaseline hybrid-resolution claims
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the hybrid-resolution row reflects the new bounded contract instead of the current one.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the selected hybrid slice is proven end to end.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep hybrid expansion sidecar-backed and explicit | The current Zig contract is built around deterministic sidecar data, not live resolver sessions. |
| Choose one concrete ambiguity family per pass | Hybrid resolution is correctness-sensitive and should stay narrowly verified. |
| Keep docs conservative unless full-compare evidence improves | This row is easy to overstate if the fixture slice stays too small. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
