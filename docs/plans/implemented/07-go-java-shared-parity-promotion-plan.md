# Plan: Go Java Shared Parity Promotion

## Goal
Promote Go and Java from verified Zig-side expansion to strict shared parity wherever the current Zig-vs-C evidence can be made to agree.

## Current Phase
Completed

## File Map
- Archive: `docs/plans/implemented/07-go-java-shared-parity-promotion-plan.md`
- Archive: `docs/plans/implemented/07-go-java-shared-parity-promotion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/language-support.md`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`

## Phases

### Phase 1: Identify promotable Go and Java deltas
- [x] Re-run the current Go and Java fixtures in zig-only and full-compare modes and list the exact remaining row-shape or ownership deltas blocking strict shared parity claims.
- [x] Separate deltas that belong to Go-only extraction debt, Java fixture shape, or harness normalization so the promotion target is explicit.
- [x] Record the exact promotable rows and any intentionally retained non-overlap in `docs/plans/implemented/07-go-java-shared-parity-promotion-progress.md`.
- **Status:** completed

### Phase 2: Close the bounded language deltas
- [x] Confirm that no extractor or pipeline change is required because the remaining deltas were fixture-contract scope, not parser defects.
- [x] Tighten the public manifest to assert only the measured shared Go and Java rows that both implementations actually agree on.
- [x] Refresh the affected manifest assertions and goldens only after the Go and Java fixture set is green in both zig-only and full-compare modes.
- **Status:** completed

### Phase 3: Promote the language claims
- [x] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, `docs/language-support.md`, and `docs/interop-testing-review.md` so the Go and Java rows reflect the new measured claim level.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the promoted claim is supported by current harness evidence.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep Go and Java together in one promotion plan | The docs currently classify both as verified Zig expansions with bounded C deltas. |
| Promote only rows that survive the full compare | The point of this plan is to turn local expansion into shared parity, not just improve Zig in isolation. |
| Treat query-result ownership rows as the main gate | Those are the specific places where the current claim still stops short. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
