# Progress

## Session: 2026-04-20

### Phase 1: Choose the next query-contract tranche
- **Status:** completed
- Actions:
  - Created the fuller Cypher/query parity plan as backlog item `03`.
  - Scoped it to a measurable read-only query tranche instead of a vague “finish all Cypher” backlog.
  - Inventoried the already-verified floor and selected the next direct-overlap tranche from the existing Zig engine coverage: aggregate counts, `OR`/`AND` precedence, and numeric `start_line` predicates.
  - Confirmed those candidate shapes overlap between Zig and C on direct probes against `testdata/interop/python-parity`.
  - Designed a dedicated `cypher-predicate-floor` fixture under `testdata/interop/cypher-expansion/predicate-floor` to make that tranche explicit in the public harness.
- Files modified:
  - `docs/plans/in-progress/03-full-cypher-query-parity-depth-plan.md`
  - `docs/plans/in-progress/03-full-cypher-query-parity-depth-progress.md`

### Phase 2: Implement and verify the next query slice
- **Status:** completed
- Actions:
  - Added the `cypher-predicate-floor` fixture and corresponding manifest assertions covering aggregate counts, boolean-precedence predicates, and numeric property predicates.
  - Confirmed the new fixture is an exact Zig/C match on direct probes before refreshing the harness baselines.
  - Determined that no `src/cypher.zig`, `src/query_router.zig`, or `src/mcp.zig` source change was required because the selected query tranche already worked end to end; the gap was public harness coverage rather than implementation support.
  - Refreshed the interop goldens with the new fixture included.
- Files modified:
  - `testdata/interop/cypher-expansion/predicate-floor/main.py`
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/`

### Phase 3: Rebaseline the query-parity claim
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Measured the new full-compare baseline at:
    - `32` fixtures
    - `244` comparisons
    - `139` strict matches
    - `37` diagnostic-only comparisons
    - `0` mismatches
    - `cli_progress: match`
  - Updated the parity docs so the shared `query_graph` floor now explicitly includes aggregate counts, boolean-precedence predicates, and numeric property predicates.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
