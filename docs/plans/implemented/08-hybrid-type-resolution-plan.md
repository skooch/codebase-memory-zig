# Plan: Hybrid Type Resolution

## Goal
Land a bounded first hybrid-resolution slice by accepting explicit repository
sidecar call targets for parser-backed Go fixtures, preferring those explicit
targets over heuristic registry matches while keeping the existing registry path
as the fallback.

## Current Phase
Completed

## File Map
- Modify: `CLAUDE.md`
- Modify: `scripts/bootstrap_worktree.sh`
- Modify: `src/pipeline.zig`
- Modify: `src/root.zig`
- Create: `src/hybrid_resolution.zig`
- Create: `testdata/interop/hybrid-resolution/`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/plans/new/README.md`
- Modify: `docs/plans/implemented/08-hybrid-type-resolution-plan.md`
- Modify: `docs/plans/implemented/08-hybrid-type-resolution-progress.md`

## Phases

### Phase 1: Lock the Hybrid-Resolution Contract
- [x] Re-read the original hybrid-resolution behavior and capture the overlap
  the Zig port can reproduce without live LSP client processes.
- [x] Narrow the first slice to explicit repository sidecar data instead of a
  broad Go/C/C++ tool-process integration.
- [x] Document the supported fixture surface and fallback behavior in
  `docs/plans/implemented/08-hybrid-type-resolution-progress.md`.
- **Status:** completed

### Phase 2: Implement The First Hybrid Slice
- [x] Add `src/hybrid_resolution.zig` and extend `src/pipeline.zig` so the Zig
  port can consult explicit hybrid call targets before falling back to registry
  heuristics.
- [x] Add reproducible local fixture coverage under
  `testdata/interop/hybrid-resolution/`.
- [x] Add regression coverage for the no-sidecar fallback path.
- **Status:** completed

### Phase 3: Verify And Reclassify
- [x] Run `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`,
  `zig build`, and `zig build test`.
- [x] Reclassify the hybrid-resolution row in `docs/port-comparison.md` from
  fully deferred to a bounded partial implementation.
- [x] Record the verified Go-only slice and the remaining C/C++ deferral in
  `docs/plans/implemented/08-hybrid-type-resolution-progress.md`.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat hybrid resolution as its own plan | The original's resolver is the highest-risk remaining analysis gap and needs its own contract instead of being hidden inside general language expansion. |
| Narrow the first completed slice to Go-backed repository sidecars | The Zig port currently has parser-backed Go coverage but no parser-backed C/C++ extraction path, so a truthful first implementation had to stop short of claiming the full original Go/C/C++ surface. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `bootstrap_worktree.sh` reported success while `zig build` still failed on missing grammars | Ran the existing bootstrap command in a partially populated worktree | Fixed the script to copy missing vendored grammar subdirectories even when `vendored/grammars/` already exists, and documented the failure mode in `CLAUDE.md`. |
