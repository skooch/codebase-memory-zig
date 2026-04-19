# Plan: Positive Reads Writes Contract

## Goal
Find and prove a positive-overlap shared `WRITES` / `READS` contract, or explicitly bound the strongest non-overlap the harness can support if positive overlap is still absent.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/06-positive-reads-writes-contract-plan.md`
- Create: `docs/plans/new/06-positive-reads-writes-contract-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `src/extractor_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/edge-parity.json`
- Modify: `testdata/interop/edge-parity/`

## Phases

### Phase 1: Probe candidate positive-overlap cases
- [ ] Enumerate a small set of candidate positive `WRITES` / `READS` micro-cases across the already-supported languages and probe them in both implementations.
- [ ] Choose the strongest candidate that produces stable shared overlap, or decide explicitly that only bounded non-overlap is currently provable.
- [ ] Record the chosen contract and rejected micro-cases in `docs/plans/in-progress/06-positive-reads-writes-contract-progress.md`.
- **Status:** pending

### Phase 2: Implement the chosen read/write contract
- [ ] If a positive-overlap case exists, extend `src/extractor.zig`, `src/pipeline.zig`, `src/store_test.zig`, and `src/extractor_test.zig` so that case is extracted and regression-tested explicitly.
- [ ] Extend `testdata/interop/edge-parity/` and `testdata/interop/manifest.json` so the chosen contract is proven in the public harness.
- [ ] Refresh `testdata/interop/golden/edge-parity.json` only after the read/write contract is green in zig-only and full-compare runs.
- **Status:** pending

### Phase 3: Rebaseline edge-parity claims
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the `WRITES` / `READS` language reflects the measured contract.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the strongest supported shared contract is documented from fresh evidence.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Probe positive overlap before committing to implementation work | The current docs only claim a bounded zero-row contract, so positive overlap must be earned with evidence. |
| Keep the public harness edge-focused and small | Read/write semantics are easy to overfit with oversized fixtures. |
| Accept a bounded non-overlap conclusion if the evidence demands it | The goal is an honest public contract, not a forced feature claim. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
