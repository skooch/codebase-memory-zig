# Progress

## Session: 2026-04-20

### Phase 1: Choose the next parser-backed tranche
- **Status:** complete
- Actions:
  - Created the language-breadth expansion plan as backlog item `11`.
  - Scored the practical next candidates against grammar stability, declaration-shape predictability, and verification cost instead of trying to widen the parser set opportunistically.
  - Chose a single-language C# tranche because it offers high parity value with stable tree-sitter declaration nodes and a cheap verification path.
  - Classified the tranche as a Zig-only parser-backed expansion claim rather than a shared semantic-parity promotion.
- Files modified:
  - `docs/plans/implemented/11-language-breadth-expansion-plan.md`
  - `docs/plans/implemented/11-language-breadth-expansion-progress.md`

### Phase 2: Add the next language tranche
- **Status:** complete
- Actions:
  - Added the pinned C# grammar to `build.zig` and `scripts/fetch_grammars.sh`.
  - Extended `src/extractor.zig` so tree-sitter-backed extraction now recognizes C# interfaces, classes, constructors, and methods with owner linkage.
  - Added focused extractor coverage and a store-backed fixture regression for the new C# lane.
  - Added the fixture repo at `testdata/interop/language-expansion/csharp-basic/Program.cs`.
- Files modified:
  - `build.zig`
  - `scripts/fetch_grammars.sh`
  - `src/extractor.zig`
  - `src/store_test.zig`
  - `testdata/interop/language-expansion/csharp-basic/Program.cs`

### Phase 3: Rebaseline language-support claims
- **Status:** complete
- Actions:
  - Updated the language-support and comparison docs so C# is explicitly documented as a Zig-only parser-backed addition rather than a shared-parity row.
  - Rebased the backlog index so plan `12` becomes the next queued execution item.
  - Verified the selected C# tranche with build, unit tests, and direct CLI indexing plus graph queries.
- Verification:
  - `bash scripts/fetch_grammars.sh --force`
  - `zig build`
  - `zig build test`
  - `zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/csharp-basic"}'`
  - `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Class"}'`
  - `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Interface"}'`
  - `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Method"}'`
  - `zig build run -- cli query_graph '{"project":"csharp-basic","query":"MATCH (a)-[:DEFINES_METHOD]->(b:Method) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'`
- Observed results:
  - The fixture indexed to `11` nodes and `17` edges.
  - `search_graph` returned `Class Entry`, `Class Worker`, and `Interface IRunner`.
  - `search_graph` returned the method inventory `Boot`, `Helper`, `Run`, `Run`, and `Worker`.
  - `query_graph` returned `DEFINES_METHOD` rows for `Entry -> Boot`, `IRunner -> Run`, `Worker -> Helper`, `Worker -> Run`, and `Worker -> Worker`.
- Files modified:
  - `docs/language-support.md`
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`
  - `docs/plans/implemented/11-language-breadth-expansion-plan.md`
  - `docs/plans/implemented/11-language-breadth-expansion-progress.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
