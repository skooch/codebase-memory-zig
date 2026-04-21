# Plan: Semantic Search And Relatedness Parity

## Goal
Close the remaining latest-upstream semantic-layer gap by adding a real Zig
`search_graph.semantic_query` surface, persisting a lightweight semantic vector
index in `moderate` / `full` modes, and emitting `SEMANTICALLY_RELATED` edges
from the same substrate.

## Current Phase
Completed

## File Map
- Modify: `src/mcp.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/root.zig`
- Create: `src/semantic_index.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/tool-surface-parity.json`
- Create: `testdata/interop/golden/semantic-query-contract.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`
- Create: `docs/plans/in-progress/21-semantic-search-and-relatedness-parity-progress.md`

## Phases

### Phase 1: Lock the semantic contract
- [x] Re-read the released upstream `v0.6.0` `search_graph.semantic_query`
      shape and `SEMANTICALLY_RELATED` mode semantics.
- [x] Define the exact Zig semantic substrate: eligible node labels, vector
      storage format, query scoring rule, and edge-emission threshold or cap.
- **Status:** completed

### Phase 2: Implement the semantic substrate
- [x] Add persistent semantic-vector storage and query helpers in the Zig store.
- [x] Add a semantic indexing module that derives vectors from indexed symbol
      context and emits bounded `SEMANTICALLY_RELATED` edges.
- [x] Wire semantic indexing into `moderate` / `full` pipeline runs while
      leaving `fast` without semantic vectors or edges.
- **Status:** completed

### Phase 3: Expose and verify the query surface
- [x] Add `semantic_query` to `search_graph` schema and request parsing.
- [x] Return separate `semantic_results` rows with scores, while keeping the
      existing structured and BM25 paths intact.
- [x] Add focused unit coverage plus a diagnostic interop fixture for the Zig
      semantic query contract.
- **Status:** completed

### Phase 4: Reclassify parity state
- [x] Update port-state docs so `search_graph.semantic_query` and
      `SEMANTICALLY_RELATED` are no longer listed as open latest-upstream gaps
      if the implementation and verification stack are green.
- [x] Move this plan to `implemented` only after verification, merge, push, and
      cleanup are complete.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --update-golden`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`
- `git diff --check`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep `semantic_query` and `SEMANTICALLY_RELATED` in one plan | The upstream release couples both to `moderate` / `full`, and a query-only surface would leave `index_repository` and the semantic-layer docs still under-implemented. |
| Use a local lightweight vector substrate instead of external services | The repo’s stated direction is zero external dependencies for the port, and the semantic layer needs to work inside the current Zig runtime and interop harness. |
| Keep the channel vocabulary (`Channel` / `LISTENS_ON`) out of scope | That is the next remaining graph-model slice after the semantic layer lands; mixing it into this plan would cross two independent subsystems. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
