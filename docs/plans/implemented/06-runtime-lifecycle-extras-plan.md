# Plan: Runtime Lifecycle Extras

## Goal
Close the remaining runtime-lifecycle gap after the completed shutdown and update-notice slice by implementing the overlapping idle store lifecycle behavior that still separated the Zig runtime from the original.

## Current Phase
Implemented

## File Map
- Modify: `docs/plans/implemented/06-runtime-lifecycle-extras-plan.md`
- Create: `docs/plans/implemented/06-runtime-lifecycle-extras-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Create: `scripts/test_runtime_lifecycle_extras.sh`

## Phases

### Phase 1: Lock the Remaining Runtime Contract
- [x] Re-read the original idle-store and session-lifecycle behavior and capture the overlapping runtime expectations in `docs/gap-analysis.md`.
- [x] Define the exact idle-session, store-lifecycle, and runtime verification workflow in `docs/plans/implemented/06-runtime-lifecycle-extras-progress.md`.
- [x] Keep the scope explicitly limited to the remaining runtime extras instead of reopening already completed shutdown and update-notice work.
- **Status:** complete

### Phase 2: Implement Session-Lifecycle Behavior
- [x] Extend `src/main.zig` and `src/mcp.zig` so the Zig runtime can reproduce the overlapping idle-store lifecycle behavior from the original without reopening the completed shutdown/update-notice slice.
- [x] Add `scripts/test_runtime_lifecycle_extras.sh` so the lifecycle extras are testable outside of unit tests.
- [x] Add focused regression coverage for the supported lifecycle transitions instead of relying only on ad hoc manual runs.
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] Run `zig build`, `zig build test`, and `bash scripts/test_runtime_lifecycle_extras.sh` until the overlapping idle-store and session-lifecycle behavior is green.
- [x] Update `docs/port-comparison.md` so the remaining runtime-extras row moves out of `Partial` only after the lifecycle extras are verified.
- [x] Record the final verification transcript and any intentionally unsupported runtime nuances in `docs/plans/implemented/06-runtime-lifecycle-extras-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Build on the completed runtime-lifecycle slice | The repo already has signal handling and update notices; the remaining work should extend that base rather than replacing it. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
