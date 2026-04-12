# Progress: Hybrid Serving Architecture

## Status
Implemented and verified

## MCP Compatibility Decision
Yes, this is possible, and it is the preferred path.

The hybrid-serving proposal should preserve the current interoperable MCP APIs and treat them as a compatibility boundary. The architecture change belongs behind the existing `mcp.zig` handlers, not in the public protocol.

### Guardrails
- Keep existing tool names unchanged.
- Keep existing required arguments unchanged.
- Keep existing top-level result envelopes unchanged for the interoperable tools.
- Limit changes to:
  - internal routing
  - internal schemas and indexes
  - result ranking improvements
  - additive metadata only where the current comparison contract already tolerates it

## Scope Snapshot
- Product shape assumed in this proposal:
  - local
  - embedded
  - mostly single-user
  - MCP-first
  - optimized for code search, symbol lookup, snippets, change impact, and architecture summaries
- This proposal does not assume:
  - a remote multi-tenant service
  - full arbitrary Cypher as a primary user need
  - security-first whole-program data-flow analysis as the dominant workload

## Current Architecture Evidence
- `src/mcp.zig` exposes a narrow, intent-specific tool surface rather than a generic graph API.
- `src/pipeline.zig` already uses a staged local pipeline with transactional flush into SQLite.
- `src/store.zig` already models the graph naturally as node and edge tables with indexes.
- `src/cypher.zig` is intentionally narrow and query-shaped, not a full graph-query serving engine.
- `docs/algorithm-audit.md` already concludes that:
  - property graph in SQLite is the right core decision
  - direct SQLite page writing is over-complex
  - broad hand-written Cypher work is a poor next investment relative to direct SQL-backed serving

## Research and Competitor Synthesis

### Competitor Patterns
- `Sourcegraph`
  - Uses specialized substrates rather than a single graph database:
    - Zoekt for lexical search
    - SCIP for precise navigation
    - service APIs and MCP exposure on top
  - Takeaway: successful code-intel products split lexical retrieval from precise facts instead of forcing a graph store to answer every query.
- `Kythe`
  - Uses a graph schema, but its own overview emphasizes that serving systems may materialize graph facts into tabular or other optimized forms.
  - Takeaway: graph can be the semantic backbone without being the only serving shape.
- `Joern`
  - Centers on code property graphs, but its docs note a move away from general-purpose graph databases toward a custom backend.
  - Takeaway: switching to a graph-native database is not automatically the simpler or more durable path.

### Research Signals
- `Code Property Graph`
  - Supports richer static-analysis semantics and proves the value of graph-shaped program facts.
  - Takeaway: graph facts are valuable, especially for relation-heavy and security-style analysis.
- `GraphCoder`
  - Reports gains from repository-level graph retrieval for code completion.
  - Takeaway: graph-aware retrieval helps when cross-file structure matters.
- `CodexGraph`
  - Argues for graph interfaces as an aid to repository understanding by coding agents.
  - Takeaway: graph structure is useful for agentic navigation, but it does not imply a graph database should own all retrieval modes.
- `When to use Graphs in RAG`
  - Suggests graph-based retrieval should be used selectively rather than treated as a universal upgrade.
  - Takeaway: keep graph usage targeted to multi-hop and structure-heavy tasks.

## Architecture Conclusion
The repo should not pivot to Neo4j, AGE, or a Joern-style deeper code-property-graph product as its next architecture move.

The cleaner target is:
- SQLite remains the canonical local graph store.
- FTS5 becomes the default lexical retrieval substrate.
- SCIP becomes an optional precision overlay.
- MCP tools keep their current public contract and route internally to the cheapest correct substrate, with mixed-mode enrichment only where it measurably improves outcomes.

## Evaluation Criteria
- Correctness
  - No regression in existing graph-heavy tools
  - Stable symbol identity across native and imported facts
- Simplicity
  - No remote services required
  - No hard dependency on external indexers for baseline indexing
- Performance
  - Faster or equal `search_code`
  - Similar or better `get_code_snippet`
  - No material regression in indexing time without imported overlays
- Product coherence
  - MCP contracts stay stable
  - Unsupported languages still behave well without SCIP
  - Existing interoperability fixtures continue to pass without client-side changes

## Resolved Scope
- First SCIP slice:
  - repo-local normalized sidecar at `.codebase-memory/scip.json`
  - exercised on a TypeScript fixture first
  - optional on every index run, never required for success
- FTS5 scope:
  - full file-body candidate generation first
  - graph-aware ranking and dedup stay in the router
- Serving split:
  - `search_code` prefers FTS5
  - `get_code_snippet` prefers graph metadata and filesystem spans, then falls back to SCIP overlay symbols
  - `get_architecture` stays graph-native behind the router
  - `detect_changes` keeps graph blast radius and can surface overlay-only symbols from changed files

## First Verification Pass
- Compare baseline versus prototype on:
  - index time
  - database size
  - peak RSS
  - `search_code` latency
  - `get_code_snippet` latency
  - `get_architecture` latency
  - `detect_changes` latency
- Re-run the existing interoperability checks to confirm there is no MCP surface drift.
- Use at least:
  - the existing interop fixtures
  - this repo
  - one medium real repository with mixed languages

## Current Slice Outcome
- Implemented an initial internal lexical index in `src/search_index.zig`.
- Added SQLite search-document storage and query helpers in `src/store.zig`.
- Enabled `FTS5` in the vendored SQLite build flags.
- Refreshed the lexical index during pipeline indexing.
- Routed `search_code` to use indexed candidate files first while preserving the existing exact line-matching and MCP response path as a fallback.
- Added `src/query_router.zig` and moved `search_code`, `get_code_snippet`, `get_architecture`, and `detect_changes` substrate orchestration behind it.
- Added `src/scip.zig` plus `scip_documents`, `scip_symbols`, and `scip_occurrences` tables in `src/store.zig`.
- Wired optional SCIP sidecar import into `src/pipeline.zig`.
- Added a fixture-backed SCIP sidecar at `testdata/interop/scip/.codebase-memory/scip.json` and corresponding regression coverage.
- Expanded the benchmark manifest to cover `search_code`, `get_code_snippet`, `get_architecture`, and `detect_changes`, including a worktree-scale repo lane.

## Verification Notes
- `zig build`: passed
- `zig build test`: passed
- `bash scripts/run_interop_alignment.sh`: passed
  - `mismatches`: `0`
  - `fixtures`: `11`
  - `strict matches`: `63`
  - `diagnostic comparisons`: `11`
  - `cli_progress`: `match`
- `bash scripts/run_benchmark_suite.sh`: passed
  - fixture corpus plus worktree-scale lane completed
  - `search_code`, `get_code_snippet`, `get_architecture`, and `detect_changes` are now benchmarked
  - Zig stayed materially faster on indexing and the new search/snippet lanes
  - medium repo indexing:
    - Zig: `2902.529 ms`
    - C: `26169.993 ms`
  - medium repo `search_code`:
    - Zig: `25.279 ms`
    - C: `608.379 ms`
  - medium repo `get_architecture`:
    - Zig: `35.165 ms`
    - C: `34.685 ms`
  - medium repo `detect_changes`:
    - Zig: `12.514 ms`
    - C: `12.196 ms`
- Reports:
  - `.interop_reports/interop_alignment_report.json`
  - `.interop_reports/interop_alignment_report.md`
  - `.benchmark_reports/benchmark_report.json`
  - `.benchmark_reports/benchmark_report.md`
- During verification, a pre-existing iterator invalidation bug surfaced in `src/test_tagging.zig`:
  - `runPass` iterated the live edge slice while appending derived edges to the same buffer
  - the durable fix was to iterate over the original edge count instead of a live slice
- Fresh worktrees in this repo may need `vendored/grammars/` and `vendored/tree_sitter/` copied from the primary checkout before Zig verification can run; `bash scripts/bootstrap_worktree.sh [primary-checkout]` now formalizes that bootstrap step

## Source Notes
- Local repo references:
  - `/Users/skooch/projects/codebase-memory-zig/src/mcp.zig`
  - `/Users/skooch/projects/codebase-memory-zig/src/pipeline.zig`
  - `/Users/skooch/projects/codebase-memory-zig/src/store.zig`
  - `/Users/skooch/projects/codebase-memory-zig/src/cypher.zig`
  - `/Users/skooch/projects/codebase-memory-zig/docs/algorithm-audit.md`
- External references:
  - Sourcegraph architecture: https://sourcegraph.com/docs/admin/architecture
  - Sourcegraph code navigation: https://sourcegraph.com/docs/code-navigation
  - SCIP: https://github.com/scip-code/scip
  - Sourcegraph MCP: https://sourcegraph.com/docs/api/mcp
  - Kythe overview: https://kythe.io/docs/kythe-overview.html
  - Joern code property graph docs: https://docs.joern.io/code-property-graph/
  - GraphCoder: https://arxiv.org/abs/2406.07003
  - CodexGraph: https://arxiv.org/abs/2408.03910
  - When to use Graphs in RAG: https://arxiv.org/abs/2506.05690
  - Code Property Graph paper: https://comsecuris.com/papers/06956589.pdf
