# Plan: Search Graph Query Parity

## Goal
Close the latest-upstream `search_graph.query` gap by adding the released BM25
query path to the Zig MCP surface, with direct contract coverage and updated
port-state docs.

## Current Phase
Completed

## File Map
- Modify: `src/mcp.zig`
- Modify: `src/store.zig`
- Modify: `src/search_index.zig`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`
- Create: `docs/plans/implemented/19-search-graph-query-parity-progress.md`

## Phases

### Phase 1: Lock the released `query` contract
- [x] Re-read the released upstream `v0.6.0` `search_graph` schema and handler
      so the Zig slice follows the BM25 `query` path rather than inventing a
      different surface.
- [x] Decide the local contract boundary between `query` and the still-missing
      `semantic_query` path, including what response fields Zig should emit now.
- **Status:** completed

### Phase 2: Implement the Zig query path
- [x] Add `query` to the Zig `search_graph` schema and request parsing.
- [x] Add a file-backed BM25 node-search path over the existing FTS tables that
      returns ranked node rows, total count, and `search_mode:"bm25"`.
- [x] Keep the existing structured-filter path intact when `query` is absent or
      produces no usable tokens.
- **Status:** completed

### Phase 3: Verify and reclassify
- [x] Add focused unit coverage for the new `tools/list` schema, the BM25 query
      response shape, and fallback behavior when the query has no usable terms.
- [x] Update the parity docs so `search_graph` stops overstating the remaining
      latest-upstream gap after `query` lands.
- [x] Move this plan to `implemented` only after the verification stack is
      green.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Scope this slice to `search_graph.query` only | It closes a real latest-upstream public contract gap without dragging in embeddings, vector search, or `moderate` indexing. |
| Reuse the existing FTS substrate instead of inventing a second index | The repo already ships `search_documents` with BM25 support, so the durable fix is to expose that capability through `search_graph` rather than duplicate indexing. |
| Keep `semantic_query` explicitly out of scope for this slice | The released upstream `query` path is independently useful and implementable on the current Zig substrate, while `semantic_query` still depends on the larger semantic-edge and vector-search backlog. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Initial build failed on an unused `readCountRow` receiver parameter | Compiled the new store helper directly after the first patch set | Marked the receiver unused, reran formatting, then reran the full verification stack. |
