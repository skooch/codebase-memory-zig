# Plan: Positive Reads Writes Contract

## Goal
Find and prove a positive-overlap shared `WRITES` / `READS` contract, or explicitly bound the strongest non-overlap the harness can support if positive overlap is still absent.

## Current Phase
Completed

## File Map
- Archive: `docs/plans/implemented/06-positive-reads-writes-contract-plan.md`
- Archive: `docs/plans/implemented/06-positive-reads-writes-contract-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/python-parity.json`
- Modify: `testdata/interop/golden/javascript-parity.json`
- Modify: `testdata/interop/golden/typescript-parity.json`
- Modify: `docs/plans/new/README.md`

## Phases

### Phase 1: Probe candidate positive-overlap cases
- [x] Enumerate a small set of candidate positive `WRITES` / `READS` micro-cases across the already-supported languages and probe them in both implementations.
- [x] Choose the strongest candidate that produces stable shared overlap, or decide explicitly that only bounded non-overlap is currently provable.
- [x] Record the chosen contract and rejected micro-cases in `docs/plans/implemented/06-positive-reads-writes-contract-progress.md`.
- **Status:** completed

### Phase 2: Implement the chosen read/write contract
- [x] Decide explicitly that no positive-overlap case is currently provable from the measured supported-language micro-cases, so no extractor or pipeline change is warranted.
- [x] Extend `testdata/interop/manifest.json` so the strongest bounded non-overlap is proven in the public harness across the exercised Python, JavaScript, TypeScript, and local-state edge fixtures.
- [x] Refresh the affected zig-only goldens only after the wider bounded non-overlap contract is green in zig-only and full-compare runs.
- **Status:** completed

### Phase 3: Rebaseline edge-parity claims
- [x] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the `WRITES` / `READS` language reflects the measured contract.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the strongest supported shared contract is documented from fresh evidence.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Probe positive overlap before committing to implementation work | The current docs only claim a bounded zero-row contract, so positive overlap must be earned with evidence. |
| Keep the public harness edge-focused and small | Read/write semantics are easy to overfit with oversized fixtures. |
| Accept a bounded non-overlap conclusion if the evidence demands it | The goal is an honest public contract, not a forced feature claim. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
