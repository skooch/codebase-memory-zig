# Plan: Hybrid Type Resolution

## Goal
Close the original's most technically distinctive analysis gap by adding the shared hybrid type-resolution layer for languages that depend on LSP-assisted or compiler-assisted symbol resolution.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md`
- Create: `docs/plans/new/ready-to-go/08-hybrid-type-resolution-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/registry.zig`
- Modify: `src/config.zig`
- Create: `src/hybrid_resolution.zig`
- Create: `testdata/interop/hybrid-resolution/`

## Phases

### Phase 1: Lock the Hybrid-Resolution Contract
- [ ] Re-read the original hybrid-resolution behavior for Go, C, and C++ and capture the overlapping contract in `docs/gap-analysis.md`.
- [ ] Define the supported external-tool assumptions, fixture set, and verification workflow in `docs/plans/new/ready-to-go/08-hybrid-type-resolution-progress.md`.
- [ ] Keep the first slice limited to shared hybrid-resolution behavior instead of bundling it with general language expansion.
- **Status:** pending

### Phase 2: Implement Hybrid Resolution Infrastructure
- [ ] Add `src/hybrid_resolution.zig` and extend `src/config.zig`, `src/extractor.zig`, `src/pipeline.zig`, and `src/registry.zig` so the Zig port can consult external resolution data for the targeted languages.
- [ ] Add local fixtures under `testdata/interop/hybrid-resolution/` that prove the selected hybrid-resolution behavior on reproducible examples.
- [ ] Add focused regression coverage that locks the supported fallback behavior when external resolution data is unavailable.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and the hybrid-resolution fixture checks until the accepted overlap for the targeted languages is stable.
- [ ] Update `docs/port-comparison.md` so the hybrid-resolution rows move out of `Deferred` only after the shared hybrid contract is verified.
- [ ] Record the final verification transcript and any intentionally unsupported resolver integrations in `docs/plans/new/ready-to-go/08-hybrid-type-resolution-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat hybrid resolution as its own plan | This is the highest-risk technical gap on the backlog and needs a dedicated contract and proof path instead of being hidden inside language expansion. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
