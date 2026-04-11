# Plan: Review Follow-Up Resolutions

## Goal
Fix the validated relation-layer correctness bugs from the review pass, record the reclassified contract-debt items, and close the work with green verification.

## Current Phase
Complete

## File Map
- Modify: `docs/plans/implemented/review-followup-resolution-plan.md`
- Modify: `docs/plans/implemented/review-followup-resolution-progress.md`
- Modify: `src/graph_buffer.zig`
- Modify: `src/pipeline.zig`
- Modify: `docs/gap-analysis.md`

## Phases

### Phase 1: Track the validated resolution set
- [x] Write the reviewed resolution set into a dedicated plan with the exact validated scope: fix self-call suppression, stop swallowing relation insertion failures, and record the ownership/type-edge items as deferred contract work.
- [x] Create a progress log for execution updates and verification notes.
- [x] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before code changes begin.
- **Status:** complete

### Phase 2: Fix relation-layer correctness bugs
- [x] Update `src/graph_buffer.zig` so valid self-referential edges can be stored instead of being dropped at insertion time.
- [x] Update `src/pipeline.zig` so resolved `CALLS` edges can retain self-targets and relation insertion no longer silently swallows `OutOfMemory` or unexpected graph-buffer failures.
- [x] Add or extend regression coverage in `src/graph_buffer.zig` and `src/pipeline.zig` for self-call preservation and duplicate-safe relation insertion.
- **Status:** complete

### Phase 3: Record deferred contract work and close out
- [x] Update `docs/gap-analysis.md` to record that Python ownership drift and broader TS/Rust type-usage drift remain contract-design work, not immediate bug fixes, and that `Constant` labeling remains intentional.
- [x] Re-run `zig build` and `zig build test`, and check `command -v zlint` so optional lint verification is reported accurately.
- [x] Move the plan and progress files from `docs/plans/in-progress/` to `docs/plans/implemented/` only after required verification is complete.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Fix only the two relation-layer issues in this execution slice | Systemic review validated self-call suppression and swallowed insertion failures as correctness bugs; the other findings were reclassified as contract debt or intentional taxonomy. |
| Record ownership and type-edge questions in docs instead of “fixing” them toward C behavior | The project contract is interoperability of public behavior and mechanisms, not imitation of legacy bugs or narrower semantics. |
| Keep `Constant` as a real label | The richer taxonomy is intentional in the Zig port and should not be collapsed just to resemble another implementation. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
