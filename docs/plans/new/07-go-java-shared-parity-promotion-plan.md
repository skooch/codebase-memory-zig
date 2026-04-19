# Plan: Go Java Shared Parity Promotion

## Goal
Promote Go and Java from verified Zig-side expansion to strict shared parity wherever the current Zig-vs-C evidence can be made to agree.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/07-go-java-shared-parity-promotion-plan.md`
- Create: `docs/plans/new/07-go-java-shared-parity-promotion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/language-support.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/go-basic.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `testdata/interop/golden/java-basic.json`
- Modify: `testdata/interop/language-expansion/java-basic/`
- Modify: `testdata/interop/go-parity/`

## Phases

### Phase 1: Identify promotable Go and Java deltas
- [ ] Re-run the current Go and Java fixtures in zig-only and full-compare modes and list the exact remaining row-shape or ownership deltas blocking strict shared parity claims.
- [ ] Separate deltas that belong to Go-only extraction debt, Java fixture shape, or harness normalization so the promotion target is explicit.
- [ ] Record the exact promotable rows and any intentionally retained non-overlap in `docs/plans/in-progress/07-go-java-shared-parity-promotion-progress.md`.
- **Status:** pending

### Phase 2: Close the bounded language deltas
- [ ] Adjust `src/extractor.zig` and `src/pipeline.zig` so the exercised Go and Java fixture rows align with the intended shared contract.
- [ ] Add or tighten store-level regression coverage for the owned definitions and query-result rows that currently block strict parity claims.
- [ ] Refresh the affected manifest assertions and goldens only after the Go and Java fixture set is green in both zig-only and full-compare modes.
- **Status:** pending

### Phase 3: Promote the language claims
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/language-support.md` so the Go and Java rows reflect the new measured claim level.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the promoted claim is supported by current harness evidence.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep Go and Java together in one promotion plan | The docs currently classify both as verified Zig expansions with bounded C deltas. |
| Promote only rows that survive the full compare | The point of this plan is to turn local expansion into shared parity, not just improve Zig in isolation. |
| Treat query-result ownership rows as the main gate | Those are the specific places where the current claim still stops short. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
