# Plan: Post-Readiness Zig Port Execution

## Goal
Break the remaining Zig port into dependency-aware phases that maximize delivered functionality per phase while keeping verification and integration risk manageable.

## Current Phase
Phase 5

## File Map
- Create: `docs/plans/in-progress/post-readiness-zig-port-execution-plan.md`
- Create: `docs/plans/in-progress/post-readiness-zig-port-execution-progress.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `docs/gap-analysis.md`

## Phases

### Phase 1: Lock the Post-Readiness Execution Strategy
- [x] Rewrite the remaining port backlog into a small number of dependency-driven execution tracks instead of the older coarse milestone list.
- [x] Define explicit sequencing rules for which subsystems must land before higher-level tool work begins.
- [x] Record which completed readiness-slice work is now treated as foundation rather than backlog.
- [x] Document which items remain optional, deferred, or productization-only after the core port reaches daily-use parity.
- **Status:** complete

### Phase 2: Complete the Core Graph and Query Substrate
- [x] Finish the remaining store/query/traversal/schema primitives that multiple tools depend on, including richer search, BFS-style traversal helpers, schema reads, and project/node/edge lifecycle helpers needed to expose the low-risk MCP surface.
- [x] Finish graph-buffer capabilities needed for durable core behavior, especially edge deduplication, ID-safe lookups, and store flush/merge paths that later watcher/incremental work will rely on.
- [x] Finish FQN and registry foundations needed for broader call/import resolution beyond the current readiness heuristics.
- [x] Exit this phase only when higher-level MCP tool work can reuse stable store/graph/registry APIs instead of re-implementing one-off query logic for the low-risk Phase 3 handlers.
- **Status:** complete

### Phase 3: Expand the Low-Risk MCP Surface
- [x] Implement the MCP tools that sit closest to already-available graph data and need limited new indexing semantics: `get_code_snippet`, `get_graph_schema`, `delete_project`, and `index_status`.
- [x] Decide whether ADR support belongs in this phase or a later productization phase; if it stays here, implement only the minimal durable ADR store/read/update path needed for parity.
- [x] Add direct regression coverage for each newly exposed tool and document any temporary contract differences from the C version.
- [x] Exit this phase only when the Zig port offers a broader but still low-risk public surface without depending on full Cypher parity or watcher/incremental infrastructure.
- **Status:** complete

### Phase 4: Raise Indexing Fidelity to Daily-Use Parity
- [x] Complete the remaining extraction and graph-fidelity work that materially improves query usefulness: richer import resolution, fuller call resolution strategy coverage, usage/type-reference edges, stronger semantic edges, and broader FQN handling.
- [x] Promote readiness-scope heuristics that are still known weak points into explicit implementation work or explicit deferrals with rationale.
- [x] Add fixture and regression coverage that proves the graph gets more useful without regressing the now-stable readiness baseline.
- [x] Exit this phase only when the graph model is reliable enough that advanced tools will be limited mainly by query/runtime gaps rather than missing graph facts.
- **Status:** complete

### Phase 5: Implement the Heavy Query and Analysis Surface
- [ ] Expand `search_graph` toward fuller parity, including richer filters, sorting, pagination, relationship/degree-aware queries, and connected-node options where they remain in-scope.
- [ ] Port the fuller Cypher parser/executor surface in a staged way, prioritizing the query shapes needed by `query_graph`, `get_architecture`, and `detect_changes`.
- [ ] Implement the higher-complexity analysis tools that depend on the stronger substrate and richer graph fidelity: `search_code`, `get_architecture`, and `detect_changes`.
- [ ] Exit this phase only when the Zig port can answer the main day-to-day analysis workflows without requiring the original C implementation as a fallback.
- **Status:** pending

### Phase 6: Add Runtime Lifecycle and Scale Features
- [ ] Implement watcher-driven auto-index, then incremental indexing, in that order, so background reindex behavior is built on a stable full-index path first.
- [ ] Implement parallel extraction and graph-buffer merge behavior only after the single-threaded indexing path and graph invariants are fully stable.
- [ ] Bring MinHash/LSH similarity and related performance-sensitive features online after the indexing/runtime lifecycle is stable enough to benchmark meaningfully.
- [ ] Exit this phase only when the port is functionally strong in both one-shot and long-running use, and performance work has a trustworthy baseline to optimize against.
- **Status:** pending

### Phase 7: Finish Productization and Deferred Value Features
- [ ] Implement CLI parity (`install`, `uninstall`, `update`, `config`, progress output) after the underlying runtime/tool surface is settled enough to avoid churn in installer-facing behavior.
- [ ] Reassess deferred-but-valuable features such as route nodes, test tagging, config-linking, git-history coupling, and decorator enrichment, and promote only the ones that still align with product goals.
- [ ] Refresh `docs/zig-port-plan.md` and `docs/gap-analysis.md` to distinguish completed parity, intentionally deferred work, and remaining long-tail gaps.
- [ ] Exit this phase only when the remaining backlog is either intentionally deferred or clearly outside the project’s target parity scope.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Prefer dependency-driven phases over the older broad milestone buckets | The repo already has a working readiness slice, so the next best sequencing should minimize rework and maximize leverage across multiple tools. |
| Finish shared graph/store/registry substrate before expanding the full public surface | This avoids building multiple MCP handlers on ad-hoc query paths that would later need to be reworked. |
| Delay watcher/incremental/parallel work until after single-threaded correctness and graph invariants are stronger | Concurrency and lifecycle work multiplies debugging cost if the underlying indexing semantics are still moving. |
| Treat CLI/productization as a late phase | Installer/config UX is cheaper to finalize once the runtime/tool contracts are more stable. |
| Treat deeper local-dataflow usage inference, override inference, and non-target-language semantic parity as explicit post-Phase-4 work | The current daily-use slice now has durable call/import/usage/semantic coverage for Python, JS/TS/TSX, Rust, and Zig, while the remaining fidelity gaps are broader parity work rather than blockers for Phase 5 query expansion. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
