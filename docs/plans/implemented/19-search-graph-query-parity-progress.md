# Progress: Search Graph Query Parity

## 2026-04-21

- Started the `search_graph.query` slice from
  `docs/plans/implemented/19-search-graph-query-parity-plan.md`.
- Confirmed the released upstream `v0.6.0` `search_graph` contract now has a
  dedicated BM25 `query` path in addition to the older structured-filter path
  and the still-missing vector-backed `semantic_query`.
- Confirmed the local Zig port still exposes only the structured search schema
  and handler path:
  - `src/mcp.zig` does not advertise `query`
  - `src/store.zig` only exposes degree-aware structural search
  - `src/search_index.zig` already maintains the FTS substrate used by
    `search_code`, so the missing piece is public MCP routing rather than raw
    index availability
- Implemented the BM25-backed Zig path:
  - `src/mcp.zig` now advertises `search_graph.query`, routes it ahead of the
    structured path, and emits `search_mode:"bm25"` plus ranked node rows.
  - `src/search_index.zig` now exposes the FTS query builder so the MCP layer
    can reuse the existing tokenization rules instead of inventing a second
    query compiler.
  - `src/store.zig` now joins ranked `search_documents` hits back to graph
    nodes, filters out noise labels, and applies structural label boosting.
- Added direct unit coverage for:
  - the `tools/list` `search_graph.query` schema
  - BM25-ranked query results with `query` taking precedence over
    `name_pattern`
  - fallback to the structured search path when the query has no usable terms
- Final verification for this slice:
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`39/39`)
