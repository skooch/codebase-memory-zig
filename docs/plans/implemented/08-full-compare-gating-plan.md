# Plan: Full Compare Gating

## Goal
Strengthen the full Zig-vs-C interop comparison so it is a more routine, visible verification gate without making the repo’s current workflows brittle or misleading.

## Current Phase
Complete

## File Map
- Move: `docs/plans/new/08-full-compare-gating-plan.md` -> `docs/plans/implemented/08-full-compare-gating-plan.md`
- Move: `docs/plans/new/08-full-compare-gating-progress.md` -> `docs/plans/implemented/08-full-compare-gating-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `docs/plans/new/README.md`
- Modify: `.github/workflows/interop-nightly.yml`

## Phases

### Phase 1: Define the stronger gating posture
- [x] Review the current CI, nightly, and local verification split and decide which parts of the full compare can be promoted into routine gating without destabilizing developer workflows.
- [x] Choose the exact gate shape, such as per-PR subset coverage, scheduled full compare plus hard visibility, or branch-conditional full compare.
- [x] Record the chosen workflow contract, failure policy, and required environment assumptions in `docs/plans/in-progress/08-full-compare-gating-progress.md`.
- **Status:** complete

### Phase 2: Implement the new verification gate
- [x] Update the relevant GitHub workflows so the chosen full-compare gate runs in the intended cadence with explicit failure handling.
- [x] Adjust `scripts/run_interop_alignment.sh` or `scripts/run_cli_parity.sh` only as needed to support the new gating mode cleanly.
- [x] Verify the workflow and script behavior locally with the same commands the docs will cite.
- **Status:** complete

### Phase 3: Rebaseline verification docs
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the verification posture is described from the new gate rather than the current nightly-only full compare.
- [x] Re-run the local verification slice needed to prove the documented gate behavior.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the repo’s claimed gate matches the checked-in workflow files.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this as verification-product work, not extraction work | The value here is confidence and visibility, not graph semantics. |
| Prefer an explicit, supportable gate over an aspirational one | The repo has already improved by removing hidden failures; this plan should continue that pattern. |
| Keep doc updates tied to the actual workflows | The verification posture must stay source-backed. |
| Keep `ci.yml` as the fast universal gate | The heavier reference comparison is valuable, but it should not block obviously unrelated docs or non-interop maintenance changes. |
| Promote the full compare into a path-scoped PR and `main` gate | Interop-touching changes now receive routine reference verification without turning every repository change into a full cross-repo build. |
| Retain the weekly sweep and manual dispatch | Scheduled runs still catch drift and environment regressions outside the path filter. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
