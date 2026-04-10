# Gap Analysis: Zig Port vs C Original

What the C codebase has that the Zig port does NOT yet have. Excludes deliberately cut features (see zig-port-plan.md Section 2 "CUT" list).

Status key: **STUB** (type signatures exist, no implementation), **MISSING** (not present at all), **PARTIAL** (some logic, incomplete)

---

## Readiness Alignment Scope (Current Gate)

For the first interoperability pass, we evaluate only this subset:

- `index_repository`
- `search_graph`
- `query_graph`
- `trace_call_path`
- `list_projects`

Parser-backed extraction behavior for this gate:

- `extractor` uses tree-sitter for:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
- Heuristic symbol extraction remains only for languages where tree-sitter support is not yet wired.
- Deferred or intentionally partial parser parity for the first gate:
  - member function/class method call target inference
  - deep import/namespace resolution across mixed project-relative paths
  - some advanced trait/impl edge cases
  - non-target language feature extraction

Comparator assumptions for this scope:

- Path values are normalized to `/`.
- Tool output order is treated as deterministic once normalized:
  - `search_graph`: name, file path, qualified name.
  - `query_graph`: column and row order as returned by the execution result.
  - `trace_call_path`: edge order is treated as an unordered set for first-pass comparison.
  - `list_projects`: sorted by project name.
- Internal IDs, watcher callbacks, and deferred/missing modules are ignored unless explicitly promoted.
- CUT and DEFER sections in the larger plan are out-of-scope for mismatch scoring during this gate.

#### Readiness diff tolerance

- **Accepted differences**
  - Unstable numeric IDs in response payloads (`nodes.id`, trace edge IDs) are not compared.
  - Path separator normalization differences (`\\` vs `/`) are normalized before comparison.
  - Tool behavior differences limited to the first gate scope are allowed if they are documented in the current docs.
  - Extra non-`CALLS` edges in `trace_call_path` are accepted while the traversal remains direction/depth-consistent.
- **Hard failures**
  - Missing expected nodes/edges for supported symbols in `search_graph`.
  - Incorrect `index_repository` node/edge counts for the same project path and mode.
  - `query_graph` schema mismatch (`columns` order/content or row set mismatch).
  - `list_projects` field omissions (`name`, `indexed_at`, `root_path`, `nodes`, `edges`) after normalization.

---

## MCP Server (`mcp.zig` vs `mcp/mcp.c`)

The Zig stub has the 14 tool names as an enum but zero handler implementations.

| Tool | C Status | Zig Status | Complexity |
|------|----------|------------|------------|
| `index_repository` | Full (full/fast modes, cancellation, lock, auto-index) | STUB | High — needs pipeline integration, lock, watcher registration |
| `search_graph` | Full (regex, degree filter, pagination, sort, include_connected, exclude_entry_points) | STUB | High — complex query builder with 12+ parameters |
| `query_graph` | Full (Cypher lex/parse/execute, max_rows, project filter) | STUB | High — depends on Cypher engine |
| `trace_call_path` | Full (BFS, inbound/outbound/both, edge type filter, depth, risk classification) | STUB | Medium — BFS + store queries |
| `get_code_snippet` | Full (exact QN + fuzzy name, include_neighbors, source file read) | STUB | Medium — store lookup + file I/O |
| `get_graph_schema` | Full (label/type counts, relationship patterns, samples) | STUB | Low — aggregate SQL queries |
| `get_architecture` | Full (languages, packages, entry points, routes, hotspots, Louvain clusters, layers, file tree, ADR) | STUB | High — many aggregate queries, clustering |
| `search_code` | Full (grep + graph enrichment, dedup into functions, rank by importance, compact/full/files modes) | STUB | High — needs grep subprocess + graph join |
| `list_projects` | Full (name, node/edge counts, indexed_at, root_path) | STUB | Low |
| `delete_project` | Full (cascade delete nodes/edges, remove .db file, unwatch) | STUB | Low |
| `index_status` | Full (in_progress/complete, node/edge counts) | STUB | Low |
| `detect_changes` | Full (git diff → affected symbols, blast radius via BFS, risk levels) | STUB | High — git diff parsing + store queries + BFS |
| `manage_adr` | Full (get/update/sections modes, section parsing/rendering, validation) | STUB | Medium |
| `ingest_traces` | Stub in C too ("not yet implemented") | STUB | N/A — cut feature |

**Gap: 13 tool handlers to implement** (excluding ingest_traces which was cut).

### MCP Protocol Layer

| Feature | C Status | Zig Status |
|---------|----------|------------|
| JSON-RPC 2.0 parsing (id, method, params) | Full (`cbm_jsonrpc_parse`) | STUB — `handleLine` returns null |
| JSON-RPC response formatting | Full (`cbm_jsonrpc_format_response/error`) | MISSING |
| MCP initialize handshake | Full (protocol version negotiation, capabilities) | MISSING |
| MCP tools/list response | Full (14 tool schemas with descriptions, parameter types) | MISSING |
| Tool argument extraction (string, int, bool) | Full (`cbm_mcp_get_*_arg`) | MISSING |
| MCP text result formatting | Full (`cbm_mcp_text_result`) | MISSING |
| Session auto-index on first tool call | Full (checks watcher, triggers if not indexed) | MISSING |
| Idle store eviction (300s timeout) | Full (`cbm_mcp_server_evict_idle`) | MISSING |
| File URI parsing (`file://` → path) | Full (`cbm_parse_file_uri`) | MISSING |
| Progress notifications | Full (JSON-RPC notification during indexing) | MISSING |

---

## Store (`store.zig` vs `store/store.c`)

The Zig store has the schema (tables + indexes + pragmas) and opens in-memory DBs. All CRUD operations are stubs.

### Project CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_project` | Full | STUB |
| `get_project` | Full | MISSING |
| `list_projects` | Full | MISSING |
| `delete_project` (cascade) | Full | MISSING |

### Node CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_node` (single) | Full (prepared statement) | MISSING |
| `upsert_node_batch` (bulk) | Full | MISSING |
| `find_node_by_id` | Full | MISSING |
| `find_node_by_qn` | Full | MISSING |
| `find_node_by_qn_any` (cross-project) | Full | MISSING |
| `find_nodes_by_name` | Full | MISSING |
| `find_nodes_by_name_any` (cross-project) | Full | MISSING |
| `find_nodes_by_label` | Full | MISSING |
| `find_nodes_by_file` | Full | MISSING |
| `find_nodes_by_file_overlap` (line range) | Full | MISSING |
| `find_nodes_by_qn_suffix` | Full | MISSING |
| `find_node_ids_by_qns` (batch QN→ID) | Full | MISSING |
| `count_nodes` | Full | STUB (returns 0) |
| `delete_nodes_by_project` | Full | MISSING |
| `delete_nodes_by_file` | Full | MISSING |
| `delete_nodes_by_label` | Full | MISSING |

### Edge CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `insert_edge` (single) | Full | MISSING |
| `insert_edge_batch` | Full | MISSING |
| `find_edges_by_source` | Full | MISSING |
| `find_edges_by_target` | Full | MISSING |
| `find_edges_by_source_type` | Full | MISSING |
| `find_edges_by_target_type` | Full | MISSING |
| `find_edges_by_type` | Full | MISSING |
| `find_edges_by_url_path` | Full | MISSING |
| `count_edges` | Full | STUB (returns 0) |
| `count_edges_by_type` | Full | MISSING |
| `delete_edges_by_project` | Full | MISSING |
| `delete_edges_by_type` | Full | MISSING |

### File Hash CRUD (for incremental indexing)

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_file_hash` / `upsert_file_hash_batch` | Full | MISSING |
| `get_file_hashes` | Full | MISSING |
| `delete_file_hash` / `delete_file_hashes` | Full | MISSING |

### Search

| Operation | C | Zig |
|-----------|---|-----|
| `cbm_store_search` (12+ params: label, name_pattern, qn_pattern, file_pattern, relationship, degree, sort, pagination) | Full | MISSING |
| `cbm_glob_to_like` | Full | MISSING |
| `cbm_extract_like_hints` | Full | MISSING |
| `cbm_ensure_case_insensitive` | Full | MISSING |

### Traversal

| Operation | C | Zig |
|-----------|---|-----|
| `cbm_store_bfs` (direction, edge types, max depth, max results) | Full | MISSING |
| `cbm_hop_to_risk` / `cbm_risk_label` | Full | MISSING |
| `cbm_build_impact_summary` | Full | MISSING |
| `cbm_deduplicate_hops` | Full | MISSING |

### Schema / Architecture

| Operation | C | Zig |
|-----------|---|-----|
| `get_schema` (labels, types, patterns, samples) | Full | MISSING |
| `get_architecture` (languages, packages, entries, routes, hotspots, boundaries, services, layers, clusters, file tree) | Full | MISSING |
| `cbm_louvain` (community detection) | Full | MISSING |
| ADR store/get/delete/update_sections | Full | MISSING |

### Transaction / Bulk

| Operation | C | Zig |
|-----------|---|-----|
| `begin` / `commit` / `rollback` | Full | MISSING |
| `begin_bulk` / `end_bulk` (pragma tuning) | Full | MISSING |
| `drop_indexes` / `create_indexes` | Full | MISSING |
| `checkpoint` | Full | MISSING |
| `dump_to_file` | Full | MISSING |
| `restore_from` (backup) | Full | MISSING |
| `check_integrity` | Full | MISSING |
| Batch degree counting | Full | MISSING |
| Node degree (in/out) | Full | MISSING |
| Node neighbor names | Full | MISSING |
| List distinct file paths | Full | MISSING |

---

## Graph Buffer (`graph_buffer.zig` vs `graph_buffer/graph_buffer.c`)

| Feature | C | Zig |
|---------|---|-----|
| Upsert node by QN | Full | PARTIAL (works but no properties_json passthrough) |
| Insert edge with dedup | Full (source_id, target_id, type dedup + property merge) | PARTIAL (appends without dedup) |
| Find node by QN | Full | Available via HashMap.get |
| Find node by ID | Full | MISSING |
| Find nodes by label | Full | MISSING |
| Find nodes by name | Full | MISSING |
| Find edges by source+type | Full | MISSING |
| Find edges by target+type | Full | MISSING |
| Find edges by type | Full | MISSING |
| Delete by label (cascade edges) | Full | MISSING |
| Delete by file (cascade edges) | Full | MISSING |
| Shared atomic ID source (for parallel) | Full (`_Atomic int64_t`) | MISSING |
| Merge worker gbufs (QN dedup + edge remap) | Full | MISSING |
| Dump to SQLite | Full (bulk insert path) | MISSING |
| Flush to existing store | Full | MISSING |
| Merge into store (incremental) | Full | MISSING |
| Load from DB | Full | MISSING |
| Foreach node/edge visitors | Full | MISSING |
| Edge dedup on insert | Full (key: source+target+type) | MISSING — current impl just appends |
| Edge count by type | Full | MISSING |
| Delete edges by type | Full | MISSING |

---

## Pipeline (`pipeline.zig` vs `pipeline/pipeline.c` + 20 pass files)

| Feature | C | Zig |
|---------|---|-----|
| Pipeline orchestrator (phase sequencing) | Full (7 phases) | STUB (empty `run()`) |
| File discovery integration | Full | MISSING |
| Graph buffer lifecycle | Full (create → populate → dump) | MISSING |
| Registry lifecycle | Full (build from defs → use in resolution) | MISSING |
| Cancellation (atomic flag) | Full | STUB (field exists, not wired) |
| Memory budget checking | Full | MISSING (deliberately cut per audit) |
| Project name derivation from path | Full (`cbm_project_name_from_path`) | MISSING |
| Pipeline lock (global mutex) | Full | MISSING |

### Pipeline Passes — Must Port

| Pass | C LOC | Zig Status | Purpose |
|------|-------|------------|---------|
| `pass_definitions` | ~3,158 (extract_defs.c) | MISSING | Tree-sitter → definition nodes |
| `pass_calls` | 571 | MISSING | Call resolution via registry |
| `pass_usages` | 170 | MISSING | Usage/type_ref edges |
| `pass_semantic` | 468 | MISSING | Inherits/implements/decorates |
| `pass_parallel` | 1,427 | MISSING | Thread pool orchestration |
| `pass_similarity` | 505 (minhash.c) | MISSING | MinHash near-clone detection |
| `pass_gitdiff` | ~200 | MISSING | Git diff → changed files/hunks |
| `pass_route_nodes` | 742 | MISSING (deferred) | HTTP route node creation |
| `pass_tests` | 285 | MISSING (deferred) | Test file/function tagging |
| `pass_enrichment` | ~200 | MISSING (deferred) | Decorator tag enrichment |
| `pass_configlink` | ~200 | MISSING (deferred) | Config-code linking |
| `pass_githistory` | 514 | MISSING (deferred) | Change coupling from git log |
| `pipeline_incremental` | ~400 | MISSING (deferred) | Incremental re-indexing |

### Extraction Layer (internal/cbm/)

| Component | C LOC | Zig Status |
|-----------|-------|------------|
| `extract_defs.c` (definition extraction) | 3,158 | MISSING |
| `extract_calls.c` (call site extraction) | 635 | MISSING |
| `extract_imports.c` (import extraction) | 872 | MISSING |
| `extract_usages.c` (usage extraction) | 170 | MISSING |
| `extract_semantic.c` (inherits/decorates) | 234 | MISSING |
| `extract_unified.c` (single-pass dispatcher) | 744 | MISSING |
| `extract_type_refs.c` | 361 | MISSING |
| `extract_type_assigns.c` | 197 | MISSING |
| `extract_env_accesses.c` | 215 | MISSING |
| `lang_specs.c` (per-language AST patterns) | 1,199 | MISSING |
| `cbm.c` (extraction entry point) | 452 | MISSING |
| `helpers.c` (AST traversal utilities) | 914 | MISSING |
| `service_patterns.c` (HTTP framework patterns) | 512 | MISSING |
| `ac.c` (Aho-Corasick, cut per audit) | 428 | N/A — cut |

### Tree-sitter Grammars

| Item | C | Zig |
|------|---|-----|
| 66 grammar .c files compiled into binary | Full | MISSING — build.zig pattern exists but no grammar files copied |
| Grammar → Language mapping | Full (lang_specs) | MISSING |
| Tree-sitter parser creation per language | Full | MISSING |

### LSP Integration (deferred)

| Component | C | Zig |
|-----------|---|-----|
| C LSP (include resolution, type inference) | Full (~1,000 LOC) | MISSING (deferred) |
| Go LSP (interface satisfaction, method sets) | Full (~1,000 LOC) | MISSING (deferred) |
| Type registry (symbol → type mapping) | Full | MISSING (deferred) |
| Scope analysis | Full | MISSING (deferred) |

---

## Cypher Engine (`cypher.zig` vs `cypher/cypher.c`)

| Component | C | Zig |
|-----------|---|-----|
| Lexer (50+ token types) | Full (3,412 LOC total) | PARTIAL — enum exists, no lexer logic |
| Parser (AST: patterns, WHERE, RETURN, ORDER BY, LIMIT) | Full | MISSING |
| Node/relationship pattern parsing | Full (labels, properties, variable-length paths) | MISSING |
| WHERE clause parsing (AND/OR/NOT/XOR, =, <>, =~, CONTAINS, STARTS/ENDS WITH, IN, IS NULL) | Full | MISSING |
| RETURN clause (items, aliases, aggregates, DISTINCT, ORDER BY, LIMIT, SKIP) | Full | MISSING |
| CASE expressions | Full | MISSING |
| UNION / UNWIND | Full | MISSING |
| WITH clause | Partial | MISSING |
| OPTIONAL MATCH | Not supported | N/A |
| Executor (AST → SQL → results) | Full | MISSING |
| Write operations (CREATE/DELETE/SET) | Rejected with error | MISSING |
| Max rows enforcement | Full (100k ceiling) | MISSING |

---

## Discover (`discover.zig` vs `discover/discover.c` + `language.c` + `gitignore.c`)

| Feature | C | Zig |
|---------|---|-----|
| Language detection by extension | Full (534 LOC) | PARTIAL — `StaticStringMap` with ~70 extensions |
| Language detection by filename (Makefile, CMakeLists.txt, Dockerfile, etc.) | Full | MISSING |
| .m file disambiguation (ObjC vs Magma vs MATLAB) | Full (reads first 4KB) | MISSING |
| Directory walk (recursive) | Full | STUB (returns empty) |
| Hardcoded skip dirs (.git, node_modules, build, etc.) | Full | MISSING |
| Hardcoded skip suffixes (.pyc, .png, .o, etc.) | Full | MISSING |
| Fast-mode skip patterns (.d.ts, .pb.go, etc.) | Full | MISSING |
| Fast-mode skip filenames (LICENSE, go.sum, etc.) | Full | MISSING |
| .gitignore loading and matching | Full (fnmatch semantics) | MISSING |
| .cbmignore support | Full | MISSING |
| Symlink skipping | Full | MISSING |
| User config (custom extension mappings) | Full (`userconfig.c`) | MISSING |
| Max file size filter | Supported | MISSING |

---

## Watcher (`watcher.zig` vs `watcher/watcher.c`)

| Feature | C | Zig |
|---------|---|-----|
| Watch/unwatch projects | Full | PARTIAL (list management only) |
| Git HEAD polling (`git rev-parse HEAD`) | Full | MISSING |
| Dirty tree check (`git status --porcelain`) | Full | MISSING |
| Adaptive poll interval | Full | PARTIAL (formula exists, not wired to poll loop) |
| Blocking poll loop with sleep | Full | MISSING |
| Index callback invocation | Full | MISSING — `index_fn` stored but never called |
| Stop signal (atomic) | Full | PARTIAL (field exists) |
| Per-project state (last_head, last_dirty) | Full | PARTIAL (struct has last_head field) |
| Thread-safe stop | Full | PARTIAL |

---

## Registry (`registry.zig` vs `pipeline/registry.c`)

| Feature | C | Zig |
|---------|---|-----|
| Add symbol (name, QN, label) | Full | PARTIAL (works but no string ownership) |
| Resolve by name | Full (5-strategy chain) | PARTIAL (first-match only, no strategies) |
| Import map integration | Full | MISSING |
| Same-module resolution | Full | MISSING |
| Same-package resolution | Full | MISSING |
| Import-reachable prefix check | Full | MISSING |
| Fuzzy resolve (bare name) | Full | MISSING |
| Exists check | Full | Works |
| Size | Full | Works |
| Find by name (all candidates) | Full | MISSING |
| Find by suffix | Full | MISSING |
| Label lookup | Full | MISSING |
| Confidence banding | Full | MISSING |

---

## CLI (`main.zig` vs `cli/cli.c`)

| Feature | C LOC | Zig Status |
|---------|-------|------------|
| `--version` | Full | Works |
| `--help` | Full | Works |
| `install` (10 agent auto-detection, config writing, hook setup) | ~1,200 | STUB (prints "not yet implemented") |
| `uninstall` (config removal, hook cleanup) | ~400 | STUB |
| `update` (version check, binary download, self-replace) | ~600 | STUB |
| `config list/get/set/reset` | ~300 | STUB |
| `cli <tool> <json>` (single tool invocation) | ~100 | STUB |
| `--progress` flag for CLI mode | Full | MISSING |
| Agent detection (Claude Code, Codex, Gemini, Zed, OpenCode, Antigravity, Aider, KiloCode, VS Code, OpenClaw) | Full | MISSING |
| Config persistence (`~/.cache/codebase-memory-mcp/config.json`) | Full | MISSING |
| Progress sink (stderr JSON lines) | Full | MISSING |

---

## MinHash (`minhash.zig` vs `simhash/minhash.c`)

| Feature | C | Zig |
|---------|---|-----|
| Fingerprint struct (K=64 u32 values) | Full | Works |
| Jaccard similarity | Full | Works |
| Hex encode/decode | Full | PARTIAL (encode only) |
| `cbm_minhash_compute` (AST → trigrams → signature) | Full | MISSING — needs tree-sitter integration |
| LSH index (insert, query candidates) | Full | MISSING |
| LSH parameters (32 bands x 2 rows) | Full | MISSING |
| Min-node gate (30 leaf tokens) | Full | Constant defined, not enforced |
| Same-file/same-language filtering | Full | MISSING |
| Max edges per node cap (10) | Full | MISSING |

---

## Foundation Layer (Zig stdlib replaces most, but gaps remain)

| C Component | Zig Replacement | Status |
|-------------|----------------|--------|
| `arena.c` | `std.heap.ArenaAllocator` | Available (not yet used in any module) |
| `hash_table.c` | `std.StringHashMap` / `std.AutoHashMap` | Used |
| `dyn_array.h` | `std.ArrayList` | Used |
| `str_intern.c` | `StringHashMap(void)` on arena | Not yet built |
| `str_util.c` (starts_with, ends_with, trim, etc.) | `std.mem` builtins | Available |
| `log.c` (structured JSON logging) | `std.log` | Not yet configured |
| `platform.c` (mmap, timers, CPU count, home dir) | `std.os` / `std.posix` / `std.fs` | Not yet used |
| `diagnostics.c` (perf metrics to JSON) | Nothing yet | MISSING |
| `compat_thread.c` | `std.Thread` | Not yet used |
| `compat_fs.c` (path normalization) | `std.fs.path` | Available |
| `constants.h` (buffer sizes) | Zig comptime constants | MISSING |
| `system_info.c` (RAM size, CPU count) | `std.os` | Not yet used |
| FQN computation (`fqn.c`) | Not yet built | MISSING |

---

## Summary by Priority

### P0 — Required for "can index a repo and answer queries"

- Store CRUD (nodes, edges, projects) with prepared statements
- Graph buffer → SQLite dump path
- File discovery (directory walk, gitignore, language detection)
- Tree-sitter extraction (definitions at minimum)
- Pipeline orchestrator (at least single-threaded: discover → extract → dump)
- Registry (add + basic resolve)
- MCP protocol layer (JSON-RPC parsing, initialize, tools/list)
- At least `index_repository`, `search_graph`, `query_graph`, `list_projects` tool handlers
- Cypher engine (or simplified SQL translator per audit recommendation)

### P1 — Required for feature parity with daily use

- Remaining 9 MCP tool handlers
- Call resolution (full 5-strategy chain)
- Usage/semantic/test passes
- Parallel extraction (thread pool + worker buffers)
- Watcher (git polling + auto-reindex)
- Incremental indexing
- CLI install/uninstall (agent detection)
- MinHash computation + LSH index

### P2 — Polish and deferred features

- Git history pass (change coupling)
- Route node creation
- Config-code linking
- Decorator enrichment
- CLI update (self-update)
- Diagnostics/structured logging
- Impact analysis edge-type weighting (per audit #36)

### Line count estimate

| Category | Estimated Zig LOC to write |
|----------|---------------------------|
| P0 (minimum viable) | ~8,000-10,000 |
| P1 (feature parity) | ~6,000-8,000 |
| P2 (polish) | ~3,000-4,000 |
| **Total** | **~17,000-22,000** |

Current Zig LOC (stubs): ~1,200
