# Plan: Advanced Trace Modes Parity

## Goal
Broaden `trace_call_path` from call-edge traversal into the original's richer trace surface for `calls`, `data_flow`, `cross_service`, risk labeling, and test inclusion controls.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/advanced-trace-modes-parity-plan.md`
- Create: `docs/plans/new/advanced-trace-modes-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/trace.zig`
- Modify: `src/mcp.zig`
- Modify: `src/main.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/pipeline.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Create: `testdata/interop/trace-parity/src/app.ts`

## Phases

### Phase 1: Lock the Trace Contract
- [ ] Re-read the original trace tool behavior and document the supported mode matrix, arguments, and response fields in `docs/gap-analysis.md`.
- [ ] Add a local trace fixture in `testdata/interop/trace-parity/src/app.ts` that exercises plain calls, test callers, and a cross-boundary path the original already recognizes.
- [ ] Record the exact verification target for the trace mode expansion in `docs/plans/new/advanced-trace-modes-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement Richer Trace Execution
- [ ] Add `src/trace.zig` to own mode dispatch, result shaping, risk annotation, and include-tests filtering for `trace_call_path`.
- [ ] Extend `src/mcp.zig` and `src/main.zig` so the Zig tool accepts the original's overlapping trace modes without regressing the existing call-edge traversal path.
- [ ] Update `src/store.zig`, `src/cypher.zig`, and `src/pipeline.zig` as needed so data-flow and cross-service trace modes can read the graph facts they need.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Add interop checks for the new trace modes to `scripts/run_interop_alignment.sh` and fail when the Zig output shape drifts from the original on the shared fixture.
- [ ] Re-run `zig build`, `zig build test`, and the trace-enabled interop harness until the broader tracing rows are green.
- [ ] Update `docs/port-comparison.md` so the `trace_call_path` row and any dependent summary rows move out of `Partial` only after the harness proves the richer overlap.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Isolate trace execution in `src/trace.zig` | The current trace path is already broader than a single handler and will become harder to reason about if it keeps growing inside `src/mcp.zig`. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
