# Progress

## Session: 2026-04-20

### Phase 1: Reproduce and pin the Go query residual
- **Status:** completed
- Actions:
  - Created the Go query-graph residual plan as backlog item `01`.
  - Scoped it to the single remaining hard full-compare mismatch instead of a broader Go expansion pass.
  - Reproduced the exercised `DEFINES_METHOD` query directly against both binaries on `testdata/interop/go-parity`.
  - Confirmed the exact row-shape disagreement:
    - Zig returns `Worker -> Run` for `MATCH (a:Class)-[:DEFINES_METHOD]->(b:Method) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC`
    - the current C reference returns zero rows for the same fixture and query
  - Verified that this is not a harness-only artifact by running direct `cli index_repository` and `cli query_graph` calls against isolated cache directories for both binaries.
  - Confirmed the Zig-side ownership path is intentional and already covered by existing tests:
    - `src/extractor.zig` tree-sitter Go extraction expects `Method` ownership on `Worker.Run`
    - `src/pipeline.zig` already has a store-level regression that persists `DEFINES_METHOD` edges for receiver-owned methods
  - Narrowed the remaining decision for Phase 2 to one of two real paths:
    - align Zig downward to the current shared C-visible contract for this fixture
    - or narrow the public fixture/compare contract so the Go method-ownership row is no longer treated as shared parity
- Files modified:
  - `docs/plans/in-progress/01-go-parity-query-graph-resolution-plan.md`
  - `docs/plans/in-progress/01-go-parity-query-graph-resolution-progress.md`

### Phase 2: Align Go ownership facts and fixture expectations
- **Status:** in_progress
- Actions:
  - No code or fixture contract changes landed yet.
  - Next step is to choose the resolution direction from the reproduced evidence before touching extractor logic or public harness expectations.
- Files modified:
  - none yet

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
