# Progress

## Session: 2026-04-20

### Phase 1: Identify promotable Go and Java deltas
- **Status:** completed
- Actions:
  - Created the Go and Java shared-parity promotion plan as backlog item `07`.
  - Scoped it to claim-promotion deltas rather than another broad language-expansion tranche.
  - Re-ran the current full compare in the dedicated worktree and isolated the only two fixture-contract blockers:
    - `go-parity`: a `Class -> DEFINES_METHOD -> Method` row that Zig returns and C does not
    - `java-basic`: a `main -> boot` method-call row that C returns and Zig does not
  - Probed narrower candidate queries directly against both binaries and confirmed the stable shared overlap:
    - Go:
      - `MATCH (a:Function)-[:CALLS]->(b:Function)` returns `boot -> NewWorker`
      - `MATCH (a)-[r:CALLS]->(b) WHERE r.type = "CALLS" AND a.name = "boot" RETURN DISTINCT b.name` returns `NewWorker` and `Run`
    - Java:
      - `MATCH (a:Class)-[:DEFINES_METHOD]->(b:Method)` returns identical class-owned rows
      - `MATCH (a:Method)-[:CALLS]->(b:Method) WHERE a.name = "run"` returns identical `run -> helper`
  - Concluded that the remaining blockers were fixture-contract scope, not parser or pipeline defects.
- Files modified:
  - `docs/plans/implemented/07-go-java-shared-parity-promotion-plan.md`
  - `docs/plans/implemented/07-go-java-shared-parity-promotion-progress.md`

### Phase 2: Close the bounded language deltas
- **Status:** completed
- Actions:
  - Removed the diagnostic-only Go ownership query from the public `go-parity` manifest contract.
  - Narrowed the Java method-call query to the measured shared `run -> helper` row.
  - Refreshed the affected zig-only goldens after the tightened contract passed.
- Files modified:
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/go-parity.json`

### Phase 3: Promote the language claims
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Confirmed that both `go-parity` and `java-basic` now report `query_graph: match`, `search_graph: match`, and `trace_call_path: match` in full compare mode.
  - Rebased the docs so Go and Java are now described as strict shared parity for the bounded exercised fixture contract, rather than Zig-only expansions.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/language-support.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
