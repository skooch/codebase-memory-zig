# Plan: Hybrid Serving Architecture

## Goal
Evolve the local MCP server from a mostly single-substrate graph-serving design into a hybrid code-intelligence stack that keeps SQLite as the embedded source of truth for graph facts, adds FTS5 for lexical and snippet-oriented retrieval, and supports optional SCIP import for higher-precision symbol facts where mature indexers exist.

## API Compatibility Rule
The hybrid serving work must preserve the current interoperable MCP tool surface.

- Do not rename tools.
- Do not remove existing arguments.
- Do not change required-versus-optional argument contracts in incompatible ways.
- Do not change top-level response shapes for the currently interoperable tools unless the change is strictly additive and tolerated by the existing comparison harness.
- Keep the architecture shift behind internal routing and storage boundaries so external MCP clients continue to see the same contract.

## Current Phase
Implemented

## File Map
- Create: `docs/plans/new/hybrid-serving-architecture-plan.md`
- Create: `docs/plans/new/hybrid-serving-architecture-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/mcp.zig`
- Modify: `src/store.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/graph_buffer.zig`
- Create: `src/search_index.zig`
- Create: `src/scip.zig`
- Create: `src/query_router.zig`
- Create: `src/search_index_test.zig`
- Create: `testdata/interop/scip/`

## Problem Statement
The current architecture is good at storing and traversing graph facts locally, but it asks the same substrate to answer three different workload classes:

1. Lexical and snippet-oriented retrieval
2. Precise symbol and reference lookup
3. Multi-hop relation and architecture queries

The graph store is the right tool for the third class, but it is not the best sole substrate for the first two. The architecture should route each workload to the cheapest and most accurate index that can answer it while preserving a single local product shape and a stable MCP contract.

## Compatibility Constraint
This plan is explicitly an internal-architecture change, not a protocol redesign.

- The current MCP interoperability surface remains the product contract.
- New substrates may improve ranking, precision, and latency, but they must be hidden behind the existing tools first.
- If a future capability truly needs a new MCP tool or response field, that should be proposed separately after the preserved-contract path is implemented and measured.

## Non-Goals
- Replace SQLite with a remote or operationally heavy graph database
- Expand generic Cypher coverage before the serving substrates are split cleanly
- Require SCIP for indexing to succeed
- Rebuild the product as a hosted multi-tenant search system
- Introduce embeddings as a core dependency for first-pass retrieval
- Redesign the public MCP API as part of the substrate split

## Target Architecture

### Layer 1: Canonical Local Graph Store
- Keep SQLite as the authoritative local store for projects, nodes, edges, file hashes, architecture summaries, and derived graph metadata.
- Preserve the current `discover -> extract -> graph buffer -> transactional flush` pipeline shape.
- Continue using the graph store for `search_graph`, `trace_call_path`, `get_graph_schema`, `get_architecture`, and graph-heavy portions of `detect_changes`.

### Layer 2: Lexical Search Substrate
- Add FTS5-backed indexes for file content, symbol names, and snippet retrieval inside the same SQLite database.
- Use this substrate for `search_code`, text-first symbol discovery, and snippet ranking before falling back to graph enrichment.
- Keep the first implementation embedded and local. External trigram engines such as Zoekt stay out of scope unless the product goals shift toward large remote serving.

### Layer 3: Optional Precise Facts Overlay
- Add an optional SCIP ingestion path that can populate symbol, definition, reference, and document data for supported languages.
- Treat SCIP data as an overlay that upgrades precision where available without replacing the native extractor for unsupported languages.
- Keep the graph store as the merged serving surface so MCP tools do not splinter into per-indexer product behavior.

### Layer 4: Query Routing
- Introduce an internal query router that decides which substrate to use per MCP tool and per query shape.
- Prefer direct, intent-specific execution paths over expanding a general query language.
- Allow tools to combine substrates when needed, such as `search_code` using FTS5 for candidate generation and graph facts for ranking or deduplication.
- Keep all routing decisions internal so interoperability remains pinned to the existing MCP tool names and response contracts.

## MCP Routing Contract

| MCP Tool | Primary substrate | Secondary substrate | Target behavior |
|----------|-------------------|---------------------|-----------------|
| `index_repository` | pipeline + graph buffer + SQLite | optional SCIP importer | Build graph facts, lexical indexes, and precise overlays in one local indexing pass |
| `search_graph` | SQLite graph tables | optional precise overlay for better labels and metadata | Structured graph search, pagination, degree-aware ranking, connected summaries |
| `query_graph` | SQLite graph tables via narrow query compiler | none at first | Keep read-only graph queries intentionally constrained |
| `trace_call_path` | SQLite graph tables | optional precise overlay for better edge confidence later | Multi-hop graph traversal stays graph-native |
| `get_code_snippet` | SQLite metadata + filesystem | optional precise overlay for exact span resolution | Exact span lookup should not depend on broad graph traversal |
| `get_graph_schema` | SQLite aggregates | none | Cheap graph metadata summary |
| `get_architecture` | SQLite graph tables + derived summaries | lexical index for hotspot and file summaries if needed | Precompute heavy summaries where they are repeatedly reused |
| `search_code` | FTS5 | SQLite graph tables | Candidate generation from lexical index, then graph-aware ranking and dedup |
| `detect_changes` | git diff + SQLite graph tables | optional precise overlay | Keep graph for blast radius; do not force text search to simulate impact |

## Data Model Additions
- Add FTS5 virtual tables for:
  - file content
  - symbol names and qualified names
  - snippet text with file and line anchors
- Add overlay tables for imported precise facts:
  - documents
  - occurrences
  - symbol definitions
  - symbol references
  - external symbol metadata
- Add derived summary tables or cached rows for:
  - architecture hotspots
  - entry points
  - directory summaries
  - precomputed degree or neighbor summaries where query profiling justifies them

## Module Boundaries
- `src/store.zig`
  - canonical schema, transactions, graph CRUD, summary CRUD, overlay-table ownership
- `src/search_index.zig`
  - FTS5 schema, indexing, snippet extraction, lexical candidate search
- `src/scip.zig`
  - SCIP parse/import, symbol normalization, overlay writes
- `src/query_router.zig`
  - route MCP tool calls to the correct substrate and compose mixed-mode results
- `src/pipeline.zig`
  - coordinate extractor output, graph flush, FTS5 refresh, and optional SCIP import
- `src/mcp.zig`
  - stay thin; expose stable tool contracts and delegate query decisions inward

## Phases

### Phase 1: Lock the Hybrid Contract
- [x] Capture the current tool-by-tool workload classes and document which queries are lexical, precise, graph, or mixed in `docs/gap-analysis.md`.
- [x] Record the target routing contract and out-of-scope alternatives in `docs/plans/new/hybrid-serving-architecture-progress.md`.
- [x] Freeze the current interoperable MCP contract as a non-negotiable compatibility boundary for this plan, including tool names, required arguments, and top-level response shapes.
- [x] Define the first supported SCIP ingestion scope and fallback rules so supported-language precision upgrades do not become a hard dependency.
- [x] Record the first-pass FTS5 schema, indexing triggers, and rollback strategy before any implementation begins.
- **Status:** complete

### Phase 2: Add the New Substrates
- [x] Add `src/search_index.zig` with FTS5 schema creation, refresh, and candidate search helpers.
- [x] Add `src/scip.zig` with a minimal import path for symbol and reference facts on a small supported-language slice.
- [x] Extend `src/store.zig` and `src/pipeline.zig` so graph facts, lexical indexes, and optional precise overlays are updated within a coherent local indexing lifecycle.
- **Status:** complete

### Phase 3: Route the MCP Surface
- [x] Add `src/query_router.zig` so `search_code`, `get_code_snippet`, `get_architecture`, and `detect_changes` stop leaning on a single substrate by default.
- [x] Keep `src/mcp.zig` focused on argument parsing and response shaping while routing decisions move into the internal serving layer.
- [x] Verify that MCP handlers preserve existing argument parsing and response shaping while only the backend execution path changes.
- [x] Narrow `query_graph` to the query shapes the local store can answer cleanly instead of broadening general Cypher coverage first.
- **Status:** complete

### Phase 4: Verify and Reclassify
- [x] Benchmark indexing time, peak memory, and query latency before and after the hybrid split on the existing fixture corpus plus at least one medium real repo.
- [x] Verify that `search_code` quality improves without regressing `search_graph`, `trace_call_path`, or `get_architecture`.
- [x] Re-run the current interoperability comparisons to prove that the surface-level MCP contract did not regress while the serving internals changed.
- [x] Update `docs/port-comparison.md` and `docs/gap-analysis.md` only after the new routing and indexing behavior is backed by repeatable evidence.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep SQLite as the core store | It matches the local embedded product shape and already fits the graph-heavy workloads well. |
| Add FTS5 before any external search engine | It keeps the first hybrid step embedded, portable, and operationally simple. |
| Treat SCIP as an optional precision overlay | That improves supported languages without making unsupported ones second-class. |
| Prefer intent-specific MCP routing over broader Cypher | The product surface is task-oriented, and the repo audit already flags Cypher expansion as lower-value complexity. |
| Keep graph usage selective | Graph structure is most valuable for relation-heavy queries, not for every retrieval task. |
| Preserve the current interoperable MCP surface | The architecture shift should improve internals without forcing client or harness churn. |

## Risks
| Risk | Why it matters | Mitigation |
|------|----------------|------------|
| Index drift between graph rows and lexical rows | Mixed-mode results become confusing if the same repo version is not represented everywhere | Refresh lexical and overlay writes inside the same indexing lifecycle and keep project-scoped version markers |
| SCIP import introduces inconsistent symbol identity | Mixed native and imported facts can fragment qualified-name matching | Normalize into one canonical symbol identity layer before writing overlay rows |
| FTS5 grows database size too quickly | Local portability suffers if the single-file store balloons unexpectedly | Start with project-scoped content and symbol tables, measure size, and gate optional snippet indexes behind evidence |
| Query router becomes a dumping ground | The architecture gains a second complexity hotspot instead of reducing one | Keep routing table-driven and push substrate-specific logic back into focused modules |

## Verification Targets
- `zig build`
- `zig build test`
- The existing MCP interoperability harness with no contract drift
- A repeatable search benchmark covering:
  - `search_code`
  - `search_graph`
  - `get_code_snippet`
  - `get_architecture`
  - `detect_changes`
- A fixture-backed precision check for at least one SCIP-imported language
- A local benchmark note recorded in `docs/plans/new/hybrid-serving-architecture-progress.md`

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
