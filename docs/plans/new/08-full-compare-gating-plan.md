# Plan: Full Compare Gating

## Goal
Strengthen the full Zig-vs-C interop comparison so it is a more routine, visible verification gate without making the repo’s current workflows brittle or misleading.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/08-full-compare-gating-plan.md`
- Create: `docs/plans/new/08-full-compare-gating-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/interop-nightly.yml`
- Modify: `.github/workflows/ops-checks.yml`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `scripts/run_cli_parity.sh`

## Phases

### Phase 1: Define the stronger gating posture
- [ ] Review the current CI, nightly, and local verification split and decide which parts of the full compare can be promoted into routine gating without destabilizing developer workflows.
- [ ] Choose the exact gate shape, such as per-PR subset coverage, scheduled full compare plus hard visibility, or branch-conditional full compare.
- [ ] Record the chosen workflow contract, failure policy, and required environment assumptions in `docs/plans/in-progress/08-full-compare-gating-progress.md`.
- **Status:** pending

### Phase 2: Implement the new verification gate
- [ ] Update the relevant GitHub workflows so the chosen full-compare gate runs in the intended cadence with explicit failure handling.
- [ ] Adjust `scripts/run_interop_alignment.sh` or `scripts/run_cli_parity.sh` only as needed to support the new gating mode cleanly.
- [ ] Verify the workflow and script behavior locally with the same commands the docs will cite.
- **Status:** pending

### Phase 3: Rebaseline verification docs
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the verification posture is described from the new gate rather than the current nightly-only full compare.
- [ ] Re-run the local verification slice needed to prove the documented gate behavior.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the repo’s claimed gate matches the checked-in workflow files.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this as verification-product work, not extraction work | The value here is confidence and visibility, not graph semantics. |
| Prefer an explicit, supportable gate over an aspirational one | The repo has already improved by removing hidden failures; this plan should continue that pattern. |
| Keep doc updates tied to the actual workflows | The verification posture must stay source-backed. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
