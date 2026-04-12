# Plan: Runtime Lifecycle Extras

## Goal
Close the remaining runtime-lifecycle gap after the completed shutdown and update-notice slice by implementing the broader idle-store and session-lifecycle extras that still separate the Zig runtime from the original.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-plan.md`
- Create: `docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/runtime_lifecycle.zig`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Modify: `src/watcher.zig`
- Modify: `src/store.zig`
- Create: `scripts/test_runtime_lifecycle_extras.sh`

## Phases

### Phase 1: Lock the Remaining Runtime Contract
- [ ] Re-read the original idle-store and session-lifecycle behavior and capture the overlapping runtime expectations in `docs/gap-analysis.md`.
- [ ] Define the exact idle-session, store-lifecycle, and runtime verification workflow in `docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-progress.md`.
- [ ] Keep the scope explicitly limited to the remaining runtime extras instead of reopening already completed shutdown and update-notice work.
- **Status:** pending

### Phase 2: Implement Session-Lifecycle Behavior
- [ ] Extend `src/runtime_lifecycle.zig`, `src/main.zig`, `src/mcp.zig`, `src/watcher.zig`, and `src/store.zig` so the Zig runtime can reproduce the overlapping idle-session and lifecycle behaviors from the original.
- [ ] Add `scripts/test_runtime_lifecycle_extras.sh` so the lifecycle extras are testable outside of unit tests.
- [ ] Add focused regression coverage for the supported lifecycle transitions instead of relying only on ad hoc manual runs.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and `bash scripts/test_runtime_lifecycle_extras.sh` until the overlapping idle-store and session-lifecycle behavior is green.
- [ ] Update `docs/port-comparison.md` so the remaining runtime-extras row moves out of `Partial` only after the lifecycle extras are verified.
- [ ] Record the final verification transcript and any intentionally unsupported runtime nuances in `docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Build on the completed runtime-lifecycle slice | The repo already has signal handling and update notices; the remaining work should extend that base rather than replacing it. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
