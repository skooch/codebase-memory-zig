# Progress

## Session: 2026-04-20

### Phase 1: Probe candidate positive-overlap cases
- **Status:** completed
- Actions:
  - Created the positive `WRITES` / `READS` contract plan as backlog item `06`.
  - Scoped it around proving a real positive-overlap case rather than assuming the next micro-case will work.
  - Probed both implementations directly through the MCP tool surface on the strongest currently plausible supported-language candidates:
    - `edge-parity`
    - `python-parity`
    - `javascript-parity`
    - `typescript-parity`
  - Queried both `MATCH (a)-[r:WRITES]->(b)` and `MATCH (a)-[r:READS]->(b)` for each candidate.
  - Measured the same result on both Zig and C for every candidate: zero rows for both edge families.
  - Confirmed from the current shipped Zig source and tests that no explicit `WRITES` / `READS` extractor pass is present today, so inventing one without measured C overlap would be a speculative expansion rather than parity work.
- Files modified:
  - `docs/plans/implemented/06-positive-reads-writes-contract-plan.md`
  - `docs/plans/implemented/06-positive-reads-writes-contract-progress.md`

### Phase 2: Implement the chosen read/write contract
- **Status:** completed
- Actions:
  - Chose the strongest honest contract as broader bounded non-overlap rather than a forced positive edge claim.
  - Extended the public interop manifest so `READS` is now asserted alongside the existing `WRITES` zero-row checks on:
    - `python-parity`
    - `javascript-parity`
    - `typescript-parity`
  - Kept `edge-parity` as the local-state bounded micro-case with explicit zero-row `WRITES` and `READS`.
  - Refreshed the affected zig-only goldens for the three parity fixtures after the widened non-overlap contract passed.
- Files modified:
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/python-parity.json`
  - `testdata/interop/golden/javascript-parity.json`
  - `testdata/interop/golden/typescript-parity.json`

### Phase 3: Rebaseline edge-parity claims
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Confirmed the baseline remains:
    - `33` fixtures
    - `251` comparisons
    - `143` strict matches
    - `38` diagnostic-only comparisons
    - `0` mismatches
    - `cli_progress: match`
  - Updated the comparison docs to state explicitly that the strongest supported shared contract is still bounded non-overlap across the exercised Python, JavaScript, TypeScript, and local-state micro-cases, not positive overlap.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
