# Plan: Runtime Lifecycle Parity

## Goal
Close the remaining runtime-lifecycle gaps by adding idle-session behavior, graceful shutdown handling, and startup update-notification parity without reopening the intentionally cut UI server.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/runtime-lifecycle-parity-plan.md`
- Create: `docs/plans/new/runtime-lifecycle-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Modify: `src/watcher.zig`
- Create: `src/runtime_lifecycle.zig`
- Modify: `build.zig`
- Create: `scripts/test_runtime_lifecycle.sh`

## Phases

### Phase 1: Lock the Runtime Contract
- [ ] Re-read the original runtime lifecycle behavior and capture the overlapping idle-store, shutdown, and startup-notification expectations in `docs/gap-analysis.md`.
- [ ] Define the exact runtime verification workflow in `docs/plans/new/runtime-lifecycle-parity-progress.md`, including signal tests and startup checks.
- [ ] Add `scripts/test_runtime_lifecycle.sh` as the execution target for repeatable runtime-lifecycle verification.
- **Status:** pending

### Phase 2: Implement Lifecycle Behavior
- [ ] Add `src/runtime_lifecycle.zig` to centralize signal handling, idle-session teardown, and startup notification checks instead of layering them ad hoc into `src/main.zig`.
- [ ] Extend `src/main.zig`, `src/mcp.zig`, and `src/watcher.zig` so the runtime starts, idles, and exits in the same overlapping ways the original supports.
- [ ] Update `build.zig` so any runtime-lifecycle test entrypoints or compile-time flags needed for verification are wired in explicitly.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and `bash scripts/test_runtime_lifecycle.sh` until idle-session, graceful-shutdown, and startup-notification expectations are green.
- [ ] Update `docs/port-comparison.md` so the runtime-lifecycle rows move out of `Partial` or `Deferred` only after the new runtime checks pass.
- [ ] Record the verification transcript and any remaining intentionally cut runtime behavior in `docs/plans/new/runtime-lifecycle-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep UI flags out of scope | The comparison table marks the UI server as cut, so runtime parity work should focus only on the still-open lifecycle rows. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
