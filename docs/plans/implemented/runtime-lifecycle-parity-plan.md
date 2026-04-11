# Plan: Runtime Lifecycle Parity

## Goal
Close the small shared runtime-lifecycle gaps by adding graceful shutdown handling and startup update-notification parity without reopening the intentionally cut UI server or overreaching into the broader idle-session extras.

## Current Phase
Completed

## File Map
- Modify: `docs/plans/implemented/runtime-lifecycle-parity-plan.md`
- Modify: `docs/plans/implemented/runtime-lifecycle-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/todo.md`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Modify: `src/root.zig`
- Create: `src/runtime_lifecycle.zig`
- Create: `scripts/test_runtime_lifecycle.sh`

## Phases

### Phase 1: Lock the Runtime Contract
- [x] Re-read the original runtime lifecycle behavior and capture the overlapping shutdown and startup-notification expectations in `docs/gap-analysis.md`.
- [x] Define the exact runtime verification workflow in `docs/plans/implemented/runtime-lifecycle-parity-progress.md`, including signal tests and startup checks.
- [x] Add `scripts/test_runtime_lifecycle.sh` as the execution target for repeatable runtime-lifecycle verification.
- **Status:** completed

### Phase 2: Implement Lifecycle Behavior
- [x] Add `src/runtime_lifecycle.zig` to centralize signal handling and startup notification checks instead of layering them ad hoc into `src/main.zig`.
- [x] Extend `src/main.zig`, `src/mcp.zig`, and `src/root.zig` so the runtime installs signal handlers, starts update checks on `initialize`, and injects a one-shot notice into the first post-initialize response.
- [x] Keep the broader idle-store and session-lifecycle extras explicitly out of scope for this S-sized parity slice.
- **Status:** completed

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and `bash scripts/test_runtime_lifecycle.sh` until graceful-shutdown and startup-notification expectations are green.
- [x] Update `docs/port-comparison.md` so only the implemented runtime-lifecycle rows move out of `Partial` or `Deferred` after the new runtime checks pass.
- [x] Record the verification transcript and the remaining intentionally deferred idle-store behavior in `docs/plans/implemented/runtime-lifecycle-parity-progress.md`.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep UI flags out of scope | The comparison table marks the UI server as cut, so runtime parity work should focus only on the still-open lifecycle rows. |
| Leave idle-store / session-lifecycle extras for a later plan | The original runtime does more than this S-sized slice should absorb; signal handling and startup notices are the smallest honest overlap to close now. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
