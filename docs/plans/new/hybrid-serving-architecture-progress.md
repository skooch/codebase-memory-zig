# Progress: Hybrid Serving Architecture

## Status
Not started

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

## Open Questions
- Which supported language should be the first SCIP ingestion slice?
- Should FTS5 index full file bodies immediately, or start with symbol and snippet text only?
- Does `get_architecture` need precomputed materialized summaries immediately, or only after query profiling shows repeated heavy scans?
- Should overlay facts be stored in separate tables only, or should selected normalized facts also be promoted into canonical node and edge rows?
- Which current response-field additions, if any, are already tolerated by the interop harness versus needing explicit deferral?

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
