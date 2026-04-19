# Progress

## Session: 2026-04-19

### Phase 1: Define the missing query surface
- **Status:** completed
- Actions:
  - Created the Cypher and query parity expansion plan as the second queued follow-on.
  - Scoped the plan to the read-only `query_graph` gap the comparison docs still describe as incomplete.
  - Re-ran the full compare baseline in the dedicated worktree and confirmed the broader parity surface is already down to a single residual mismatch: `go-parity/query_graph`.
  - Classified that residual as extraction-shape debt, not executor failure: Zig returns the `Class -> DEFINES_METHOD -> Method` row on the Go fixture, while the current C reference returns zero rows for the same fixture query.
  - Identified the actual shared-query evidence gap: the repo already ships node reads, edge reads, filtering, counts, distinct selection, and bounded boolean conditions in `src/cypher.zig`, but the shared fixture contract barely proves that surface today.
- Files modified:
  - `docs/plans/in-progress/02-cypher-and-query-parity-expansion-plan.md`
  - `docs/plans/in-progress/02-cypher-and-query-parity-expansion-progress.md`

### Phase 2: Expand and lock the shared read-only query floor
- **Status:** completed
- Actions:
  - Adding focused `src/cypher.zig` regression tests for `DISTINCT`, boolean-condition precedence, numeric comparisons, and edge-field filtering.
  - Expanded `testdata/interop/manifest.json` with an additional shared-query tranche covering `DISTINCT`, boolean filters, and edge-type filtering on fixtures that both implementations already agree on.
  - Refreshed the zig-only goldens and confirmed the new contract lands exactly in `testdata/interop/golden/python-basic.json`, `testdata/interop/golden/python-parity.json`, and `testdata/interop/golden/go-parity.json`.
  - Verified the broadened query floor with `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and the full `bash scripts/run_interop_alignment.sh` compare run.
  - The full compare still reports exactly one residual mismatch, unchanged in shape: `go-parity/query_graph`, where Zig returns the `Worker -> Run` method-definition row and the current C reference still returns zero rows.
- Files modified:
  - `src/cypher.zig`
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/python-basic.json`
  - `testdata/interop/golden/python-parity.json`
  - `testdata/interop/golden/go-parity.json`

### Phase 3: Reclassify the remaining gap and close the plan
- **Status:** in_progress
- Actions:
  - Updating `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` to describe the now-verified read-only Cypher floor accurately.
  - Archiving the plan and progress log only after the docs and plan indexes reflect that the remaining `go-parity/query_graph` delta is extraction-side residual debt, not broader executor incompleteness.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-19 | Prior compare session handle expired before output retrieval | Re-polled the dead PTY session | Re-read the persisted `.interop_reports/interop_alignment_report.json` in the worktree and continued from the on-disk report. |
