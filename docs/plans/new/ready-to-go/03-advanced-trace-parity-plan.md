# Plan: Advanced Trace Parity

## Goal
Expand the Zig tracing surface beyond call edges so the shared `trace_path` story looks credible as a drop-in replacement for users expecting richer traversal, include-tests behavior, and higher-level trace annotations.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/03-advanced-trace-parity-plan.md`
- Create: `docs/plans/new/ready-to-go/03-advanced-trace-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/mcp.zig`
- Modify: `src/cypher.zig`
- Modify: `src/store.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/trace-parity/`

## Phases

### Phase 1: Lock the Shared Trace Contract
- [ ] Re-read the original trace modes and capture the overlapping traversal, include-tests, and annotation expectations in `docs/gap-analysis.md`.
- [ ] Define the exact shared trace requests and expected outputs in `docs/plans/new/ready-to-go/03-advanced-trace-parity-progress.md`.
- [ ] Add trace-focused parity fixtures under `testdata/interop/trace-parity/` so richer trace behavior can be verified without relying on ad hoc external repos.
- **Status:** pending

### Phase 2: Implement Richer Trace Behavior
- [ ] Extend `src/store.zig`, `src/pipeline.zig`, and `src/cypher.zig` so the graph retains the data needed for richer trace traversal beyond the current call-edge-only path.
- [ ] Extend `src/mcp.zig` so the public trace tool can express the overlapping richer modes instead of silently flattening everything to call edges.
- [ ] Add focused regression coverage in `src/store_test.zig` and fixture-driven interop checks in `testdata/interop/manifest.json`.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and the interop trace fixture checks until the shared richer trace requests match the original on the accepted overlap.
- [ ] Update `docs/port-comparison.md` so the trace row moves out of `Partial` only after the richer traversal modes are verified.
- [ ] Record the final verification transcript and any intentionally unsupported original-only trace annotations in `docs/plans/new/ready-to-go/03-advanced-trace-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Focus on the accepted overlap first | The drop-in replacement claim depends on the trace behaviors users actually exercise, not on immediately porting every original-only risk-label nuance. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
