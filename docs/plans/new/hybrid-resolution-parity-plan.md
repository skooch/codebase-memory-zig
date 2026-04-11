# Plan: Hybrid Resolution Parity

## Goal
Add the original's LSP-assisted type and call-resolution path for Go, C, and C++ so the Zig port can match the higher-fidelity hybrid resolution lane.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/hybrid-resolution-parity-plan.md`
- Create: `docs/plans/new/hybrid-resolution-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/lsp.zig`
- Create: `src/compile_commands.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/registry.zig`
- Modify: `src/main.zig`
- Modify: `build.zig`
- Create: `testdata/interop/hybrid-resolution/compile_commands.json`
- Create: `testdata/interop/hybrid-resolution/src/main.cpp`

## Phases

### Phase 1: Lock the Hybrid Contract
- [ ] Re-read the original hybrid-resolution path and capture the overlapping LSP, compile-commands, and symbol-resolution expectations in `docs/gap-analysis.md`.
- [ ] Add a minimal compile-commands-based fixture in `testdata/interop/hybrid-resolution/` so hybrid resolution can be verified locally.
- [ ] Record tooling assumptions, environment requirements, and verification commands in `docs/plans/new/hybrid-resolution-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement LSP-Assisted Resolution
- [ ] Add `src/compile_commands.zig` and `src/lsp.zig` to parse compilation databases and broker the symbol/type lookups needed by the pipeline.
- [ ] Extend `src/pipeline.zig`, `src/registry.zig`, and `src/main.zig` so hybrid resolution can enrich the existing graph without breaking parser-only indexing paths.
- [ ] Update `build.zig` so any optional LSP integration flags or generated test fixtures are wired in explicitly.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and the hybrid-resolution fixture checks until the Go/C/C++ hybrid rows are stable.
- [ ] Update `docs/port-comparison.md` so the deferred LSP-hybrid row moves only after the fixture-backed path is proven.
- [ ] Record any required external-tool constraints in `docs/plans/new/hybrid-resolution-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep hybrid resolution in opt-in modules | That preserves the existing parser-only pipeline for users who do not have LSP infrastructure available. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
