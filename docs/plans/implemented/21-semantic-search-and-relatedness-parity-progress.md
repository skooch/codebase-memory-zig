# Progress: Semantic Search And Relatedness Parity

## 2026-04-21

- Started the semantic-layer slice in
  `docs/plans/in-progress/21-semantic-search-and-relatedness-parity-plan.md`.
- Confirmed the released upstream `v0.6.0` contract:
  - `search_graph.semantic_query` is an array of keyword strings
  - semantic hits are returned in a separate `semantic_results` array
  - `moderate` / `full` modes are the semantic-enabled indexing modes
  - the graph model also adds `SEMANTICALLY_RELATED`
- Confirmed the current Zig port still lacks all of that semantic substrate:
  - `src/mcp.zig` advertises `query` but not `semantic_query`
  - `src/pipeline.zig` has `moderate` mode now, but it still skips true
    semantic vectors and `SEMANTICALLY_RELATED`
  - `src/store.zig` has no semantic-vector storage or semantic search helper
- Added persisted semantic-vector storage in `src/store.zig` plus a new
  `src/semantic_index.zig` substrate that derives local lightweight vectors,
  emits bounded `SEMANTICALLY_RELATED` edges, and serves semantic keyword
  search.
- Wired semantic refresh into `src/pipeline.zig` for `moderate` / `full`,
  including the incremental no-change path so existing projects do not keep
  stale pre-semantic indexes forever.
- Updated `src/mcp.zig` to advertise and serve `search_graph.semantic_query`,
  return separate `semantic_results`, reject non-array semantic input with
  `-32602`, and escape quoted `query_graph` cell strings correctly.
- Added unit coverage for:
  - semantic substrate behavior on the seeded send-task fixture
  - `search_graph.semantic_query` success and type-error cases
  - quoted-string `query_graph` row serialization
- Refreshed the parity harness inputs:
  - updated `tool-surface-parity` to include the released semantic schema
  - added `semantic-query-contract` for the Zig-side semantic payload and
    `SEMANTICALLY_RELATED` row shape
  - documented the harness subprocess finalizer failure mode in `CLAUDE.md`
    and hardened `scripts/run_interop_alignment.sh` so fixture servers are
    terminated explicitly after each scenario
- Updated the port-state docs so semantic search and `SEMANTICALLY_RELATED`
  are no longer listed as open latest-upstream gaps; the remaining named
  latest-upstream graph-model delta is the channel vocabulary
  (`Channel` / `LISTENS_ON`).
