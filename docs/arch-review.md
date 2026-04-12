# Architecture Review: codebase-memory-zig

**Date:** 2026-04-12
**Scope:** Full architecture review of the Zig port of codebase-memory-mcp
**Method:** Multi-pass loop (surface -> deep -> saturation -> synthesis)
**Status:** Complete
**Passes:** 5 (surface mapping, deep validation, saturation, second deep pass, synthesis)

---

## 1. Codebase Map

### Overview

- **20 Zig source files**, 18,327 lines total
- **Binary target:** `cbm` -- MCP server (stdio) + CLI subcommands
- **External deps:** vendored SQLite amalgamation, zig-tree-sitter package, vendored grammar C files
- **Build:** `zig build` with C interop (libc linked), cross-compilation supported

### Module Map

| Module | Lines | Role | Layer |
|--------|-------|------|-------|
| `main.zig` | 766 | CLI dispatcher, MCP server boot, watcher thread | Entry |
| `mcp.zig` | 2908 | JSON-RPC 2.0 MCP protocol handler (stdio + HTTP) | Protocol |
| `cli.zig` | 621 | Agent config install/uninstall, persistent config | Config |
| `pipeline.zig` | 2572 | Multi-pass indexing orchestrator | Core |
| `extractor.zig` | 3235 | Tree-sitter AST extraction (multi-language) | Core |
| `store.zig` | 1887 | SQLite CRUD for nodes, edges, projects, FTS5, SCIP | Persistence |
| `graph_buffer.zig` | 659 | Ephemeral in-memory graph accumulator | Persistence |
| `cypher.zig` | 1239 | Read-only Cypher query parser + executor | Query |
| `query_router.zig` | 1485 | Semantic query routing, JSON payload builder | Query |
| `search_index.zig` | 132 | FTS5 text search layer | Query |
| `discover.zig` | 567 | Filesystem walker, language detection, gitignore | Support |
| `registry.zig` | 398 | Symbol resolution with confidence scoring | Support |
| `minhash.zig` | 456 | LSH near-clone detection | Support |
| `watcher.zig` | 397 | Adaptive polling for auto-reindex | Support |
| `runtime_lifecycle.zig` | 236 | Signal handling, update checks | Support |
| `test_tagging.zig` | 250 | Test metadata, derived TESTS/TESTS_FILE edges | Support |
| `scip.zig` | 236 | SCIP symbol overlay import | Support |
| `adr.zig` | ~30 | ADR markdown section extraction | Support |
| `store_test.zig` | 210 | Integration tests for store + pipeline | Test |
| `root.zig` | 48 | Module root, re-exports public API | Glue |

### Dependency Layers

```
                     +---------------+
                     |   main.zig    |  Entry point
                     +-------+-------+
                             |
              +--------------+-------------+
              |              |             |
        +-----+------+  +---+----+  +-----+------+
        |  mcp.zig   |  |cli.zig |  |  watcher   |
        | (protocol) |  |(config)|  | (polling)  |
        +-----+------+  +--------+  +------------+
              |
    +---------+-------------+
    |         |             |
+---+----+ +-+----------+ ++----------+
|pipeline| |query_router | |  cypher   |
|(index) | |(search/arch)| |(query)    |
+---+----+ +------+------+ +-----+----+
    |             |               |
    +- extractor  +- search_index |
    +- registry   +- scip         |
    +- minhash    +- discover     |
    +- test_tag   |               |
    +- scip       |               |
    |             |               |
    +-------------+-------+-------+
                          |
                 +--------+--------+
                 |    store.zig    |  SQLite persistence
                 |  graph_buffer  |  In-memory staging
                 +-----------------+
```

### Data Flow

1. **Index path:** `main` -> `pipeline` -> (`discover` -> `extractor` -> `registry` -> `minhash` -> `test_tagging` -> `scip`) -> `graph_buffer` -> `store`
2. **Query path:** `main` -> `mcp` -> (`query_router` | `cypher` | store direct) -> `store`
3. **Watch path:** `main` -> `watcher` -> callback -> `pipeline` (full loop)
4. **CLI path:** `main` -> `cli` (config files) or `main` -> direct tool dispatch

---

## 2. Themes

### T1: Migration Residue

The port from C has left dead code and duplicated logic. `mcp.zig` contains **940 lines** (40+ functions) of tool implementation logic already migrated to `query_router.zig`. Pass 2 precisely mapped the three dead clusters: old snippet handler (684-780), old architecture builder (982-1192), and old search_code/detect_changes stack (1210-1891).

### T2: Thread Safety Gaps in the Watcher Path

**(Fixed in arch-review-fixes branch)** The watcher thread and the MCP request-handler thread both mutated `Watcher.entries` without synchronization. Additionally, the watcher opens a separate SQLite connection that can collide with the MCP connection on `beginImmediate`, causing silent reindex drops.

### T3: Allocator Discipline Erosion

Several functions bypass the allocator-passing contract with bare `std.heap.page_allocator`: `cypher.zig:563,664`, `mcp.zig:1636,1643` (dead code), `query_router.zig:1350,1357`, `extractor.zig:1814`, `cli.zig:413`. The cypher and extractor cases are in hot paths (per-node condition evaluation, per-method owner lookup).

### T4: Wide Modules, Narrow Tests

`query_router.zig` (1485 lines) has zero tests. `store_test.zig` only covers happy paths. Pass 2 added: no end-to-end `extractFile` tests in extractor.zig (21 tests all unit-level), and no tests for Cypher edge cases (AND/OR precedence, variable-length paths, multi-column ORDER BY).

### T5: Query Performance at Scale

`searchGraph` uses correlated subqueries for degree computation (O(N * |edges|) per result set). BFS traversal uses N+1 SQL round-trips per frontier node. Cypher engine pre-fetches up to 100k nodes regardless of caller's `max_rows`. These are acceptable at current graph sizes but will become bottlenecks at scale.

### T6: Silent Degradation in the Pipeline

Errors in enrichment passes (test_tagging, similarity, config_link) abort the entire pipeline via `try`, rolling back a successful extraction of thousands of files. Unresolved calls are silently dropped with no record. Parallel merge can silently preserve stale local IDs on partial upsert failure. The pipeline is robust for the happy path but fragile under resource pressure.

### T7: Cypher Engine Semantic Gaps

The hand-rolled Cypher subset has three silent-wrong-result bugs: AND/OR precedence inversion in mixed WHERE clauses, variable-length path syntax parsed as edge type (returns zero rows silently), and multi-column ORDER BY dropping all but the first column. These produce wrong results without error messages.

---

## 3. Issue Register

### Pass 1 Issues

| ID | Title | Area | Status | Remediation |
|----|-------|------|--------|-------------|
| A1 | **Watcher data race**: `entries` ArrayList mutated from two threads without sync | Concurrency | **fixed** | -- |
| A2 | **Dead code in mcp.zig**: 940 lines / 40+ functions across 3 clusters | Protocol | **validated** | local refactor |
| A3 | **query_router.zig has zero test coverage** | Test | **validated** | local refactor |
| A4 | **store.zig searchGraph correlated subqueries**: degree = O(N * \|edges\|) | Performance | **validated** | track as debt |
| A5 | **store.zig BFS traversal**: N+1 SQL round-trips per frontier node | Performance | **validated** | track as debt |
| A6 | **Bare page_allocator usage**: 6+ call sites bypass allocator passing | Cross-cutting | **validated** | local refactor |
| A7 | **store.zig weak transaction discipline**: multi-table deletes not atomic | Persistence | **validated** | local refactor |
| A8 | **Parallel extraction silent failure**: no logging in worker catch blocks | Core | **fixed** | -- |
| A9 | **extractToolCall error escape**: no JSON-RPC error on malformed params | Protocol | **fixed** | -- |
| A10 | **Unchecked @intCast on JSON inputs**: panic on out-of-range values | Safety | **fixed** | -- |
| A11 | **store.zig mixes 4 domains**: wide but not tangled | Persistence | **mixed** | track as debt |
| A12 | **query_router.zig manual JSON building**: maintainability, not correctness | Query | **overstated** | track as debt |
| A13 | **Git subprocess silent failure**: detectChanges ignores exit codes | Query | **validated** | local refactor |
| A14 | **store_test.zig happy-path only**: no error path coverage | Test | **validated** | track as debt |
| A15 | **No CI interop testing**: parity harness not gated in CI | CI | **validated** | track as debt |
| A16 | **Wildcard helper duplicated 3x**: cypher, mcp (dead), query_router | Cross-cutting | **validated** | local refactor |
| A17 | **Pipeline accumulates all extraction memory**: O(files * avg_extraction) | Performance | **validated** | track as debt |

### Pass 2 Issues

| ID | Title | Area | Status | Remediation |
|----|-------|------|--------|-------------|
| A18 | **Cypher AND/OR precedence wrong**: `A OR B AND C` evaluates as `(A OR B) AND C` (cypher.zig:783-803) | Query | **validated** | local refactor |
| A19 | **Cypher variable-length paths silently misparse**: `[:CALLS*1..3]` parsed as edge type `"CALLS*1..3"`, returns 0 rows (cypher.zig:734) | Query | **validated** | local refactor |
| A20 | **Cypher OPTIONAL MATCH rejected silently**: no error message, just "unsupported query" (cypher.zig:671) | Query | **validated** | track as debt |
| A21 | **Cypher multi-column ORDER BY drops columns**: only first column used (cypher.zig:907-931) | Query | **validated** | local refactor |
| A22 | **Cypher 100k node pre-fetch**: ignores caller `max_rows`, always loads up to 100k (cypher.zig:139,175) | Performance | **validated** | track as debt |
| A23 | **Cypher generic error messages**: no position or token context on parse failure (cypher.zig:105-115) | UX | **validated** | track as debt |
| A24 | **Rust closures always promoted to Function**: floods graph with noise from iterator chains (extractor.zig:1574) | Core | **validated** | local refactor |
| A25 | **No end-to-end extractFile tests**: 21 tests all unit-level, no integration coverage | Test | **validated** | track as debt |
| A26 | **Non-OOM extraction errors silently swallowed**: TS parse and addSymbol errors invisible (extractor.zig:189-194) | Core | **validated** | track as debt |
| A27 | **Enrichment passes abort pipeline on OOM**: test_tagging, similarity, config_link use `try`; should degrade gracefully (pipeline.zig:125-127) | Core | **validated** | local refactor |
| A28 | **File hash uses mtime+size only**: stale on coarse-resolution filesystems; hash column stored as "" (pipeline.zig:468-478) | Core | **validated** | track as debt |
| A29 | **Unresolved calls silently dropped**: no low-confidence edge, no counter, no log (pipeline.zig:1120-1170) | Core | **validated** | track as debt |
| A30 | **No cancellation check between post-extraction passes**: similarity pass can run to completion after cancel requested (pipeline.zig:125-131) | Core | **validated** | local refactor |
| A31 | **Parallel merge preserves stale IDs on partial failure**: `orelse extraction.file_id` falls back to local ID that does not exist in shared buffer (pipeline.zig:674) | Core | **validated** | track as debt |
| A32 | **query_router appendPropertyFields raw-splices DB JSON**: mcp.zig version re-encodes safely, query_router version does not (query_router.zig:1450-1457) | Query | **validated** | local refactor |

---

## 4. Validated Concern Matrix

| Initial Concern | Pass 1 | Pass 2 | Evidence |
|-----------------|--------|--------|----------|
| mcp.zig concentrates too much | Confirmed | **Precise**: 940 lines, 40+ fns, 3 clusters | Dead code audit mapped every function. No tests exercise dead paths. |
| query_router JSON is risky | Overstated | **Upgraded to Mixed** | String escaping is correct via `std.json.fmt`, BUT `appendPropertyFields` raw-splices `properties_json` from DB (A32). The mcp.zig version of the same function re-encodes safely. |
| store.zig scope creep | Mixed | Mixed (unchanged) | Wide but clean. No new findings on second pass. |
| main.zig mixes concerns | Overstated | Overstated (unchanged) | -- |
| No structured error taxonomy | Deferred | Deferred (unchanged) | -- |
| Cypher engine limitations | Overstated | **Upgraded to Confirmed** | Three silent-wrong-result bugs: AND/OR precedence (A18), variable-length paths (A19), multi-column ORDER BY (A21). These produce wrong results, not errors. |
| Pipeline robustness | Not assessed | **New: Mixed** | Happy path is solid. Enrichment passes abort on OOM (A27), unresolved calls silently dropped (A29), no cancellation between passes (A30). |
| Extractor completeness | Not assessed | **New: Fine** | Memory management is correct, language dispatch is clear. One Rust-specific false positive (A24). Integration test gap (A25) but unit coverage is good. |

---

## 5. Remediation Strategy

### Phase 1: Fix Safety Issues (S-M effort) -- DONE

All four items completed on branch `arch-review-fixes`.

- **A1**: Added `std.Thread.Mutex` to `Watcher`. **Done.**
- **A9**: `extractToolCall` errors now return JSON-RPC -32602. **Done.**
- **A10**: `intArg`/`signedIntArg` use `std.math.cast`. **Done.**
- **A8**: Parallel extraction worker `catch` blocks now log warnings. **Done.**

### Phase 2: Clean Up Migration Residue + Cypher Correctness (S-M effort)

Remove dead code, deduplicate utilities, and fix the three Cypher silent-wrong-result bugs.

- **A2**: Delete 940 lines of dead tool logic from mcp.zig (3 clusters: lines 684-780, 982-1192, 1210-1891, plus stragglers).
- **A16**: Extract shared wildcard helper, delete duplicates from cypher/mcp/query_router.
- **A6**: Thread allocator through the 6+ bare `page_allocator` call sites.
- **A18**: Fix AND/OR precedence in Cypher WHERE evaluation (AND must bind tighter).
- **A19**: Reject or properly parse variable-length path syntax instead of silent misparse.
- **A21**: Support multi-column ORDER BY or reject with clear error.

### Phase 3: Pipeline Resilience + Test Coverage (M effort)

Harden the pipeline against resource pressure and add test coverage for untested layers.

- **A27**: Wrap test_tagging, similarity, and config_link passes in `catch` with log+continue instead of `try`.
- **A30**: Add cancellation checks between post-extraction passes.
- **A32**: Fix `appendPropertyFields` in query_router to re-encode via `std.json` (match the safe mcp.zig version).
- **A3**: Add integration tests for query_router's four public payload functions.
- **A13**: Check git subprocess exit codes in `collectChangedFiles`; return error on non-zero.
- **A24**: Suppress Rust `closure_expression` unless assigned to a named binding (match JS arrow function logic).

### Phase 4: Performance (L effort, when needed)

- **A4**: Materialize degree counts in a CTE or temp table instead of correlated subqueries.
- **A5**: Batch BFS queries (WHERE node_id IN (...)) instead of per-node round-trips.
- **A17**: Consider per-file arena allocators with reset between files in the pipeline.
- **A22**: Push Cypher `max_rows` down to the node fetch limit instead of post-filtering.

### Phase 5: Structural + Debt (L effort, optional)

- **A11**: Split store.zig into core_store, fts_store, scip_store if it continues growing.
- **A7**: Add internal transaction wrapper for multi-table operations in store.
- **A15**: Add interop testing to CI (compare Zig binary output against C binary on test corpus).
- **A14**: Add store error-path tests.
- **A25**: Add end-to-end `extractFile` integration tests.

---

## 6. Ranked Backlog Checklist

Ordered by dependency (what unblocks later work) then by leverage within each tier.

| # | Issue | Size | Phase | Depends On | Status |
|---|-------|------|-------|------------|--------|
| 1 | A1: Add mutex to Watcher.entries | S | 1 | -- | **DONE** |
| 2 | A9: Catch extractToolCall errors | S | 1 | -- | **DONE** |
| 3 | A10: Range-check @intCast on JSON inputs | S | 1 | -- | **DONE** |
| 4 | A8: Log parallel extraction failures | S | 1 | -- | **DONE** |
| 5 | A2: Delete 940 lines of dead code from mcp.zig | M | 2 | -- | |
| 6 | A18: Fix Cypher AND/OR precedence | S | 2 | -- | |
| 7 | A19: Reject or parse variable-length path syntax | S | 2 | -- | |
| 8 | A21: Support or reject multi-column ORDER BY | S | 2 | -- | |
| 9 | A16: Extract shared wildcard helper, delete 3 copies | S | 2 | #5 | |
| 10 | A6: Thread allocator through page_allocator sites | S | 2 | #9 | |
| 11 | A27: Wrap enrichment passes in catch instead of try | S | 3 | -- | |
| 12 | A30: Add cancellation checks between pipeline passes | S | 3 | -- | |
| 13 | A32: Fix appendPropertyFields raw JSON splice | S | 3 | -- | |
| 14 | A24: Suppress Rust closure_expression false positives | S | 3 | -- | |
| 15 | A13: Check git exit codes in query_router | S | 3 | -- | |
| 16 | A3: Add query_router integration tests | M | 3 | #5 | |
| 17 | A4: Optimize searchGraph degree queries | M | 4 | -- | |
| 18 | A5: Batch BFS traversal queries | M | 4 | -- | |
| 19 | A17: Per-file arena reset in pipeline | M | 4 | -- | |
| 20 | A22: Push Cypher max_rows to fetch limit | S | 4 | -- | |
| 21 | A7: Transaction wrapper for multi-table ops | S | 5 | -- | |
| 22 | A11: Split store.zig if growing | L | 5 | -- | |
| 23 | A15: Add interop testing to CI | L | 5 | -- | |
| 24 | A14: Add store error-path tests | M | 5 | -- | |
| 25 | A25: Add end-to-end extractFile tests | M | 5 | -- | |

---

## 7. Final Judgment

### What the architecture gets right

**The module layering is sound.** The separation between protocol (mcp), orchestration (pipeline), extraction (extractor), persistence (store), and query (cypher/query_router) is clean and intentional. Each layer has a well-defined responsibility and dependencies flow downward. This is a well-structured Zig codebase.

**Allocator discipline is strong overall.** Explicit allocator passing, arena allocators for per-file lifetimes, `errdefer` cleanup chains, and careful ownership semantics. The `page_allocator` violations are small exceptions to an otherwise excellent pattern.

**The port from C is architecturally improved.** The Zig version has cleaner module boundaries, better error handling (error unions vs. int return codes), and dropped dead features (traces, infrascan, k8s, UI server). The decisions about what to cut were good.

**Concurrency design is solid.** The atomic index-busy flag, per-worker graph buffers in parallel extraction, WAL-mode SQLite, and (now) mutex-protected watcher entries all show thoughtful concurrency design.

**Memory management is correct.** Pass 2 validated that tree-sitter parsers are freed on all paths, graph buffer dump doesn't leak, parallel workers clean up correctly, and `errdefer` chains are consistently applied. No memory leaks found.

### The most important real problems

1. **Cypher silent-wrong-result bugs (A18, A19, A21)**: AND/OR precedence, variable-length path misparse, and multi-column ORDER BY truncation all produce wrong results without any error. Users querying via the MCP `query_graph` tool will get silently incorrect answers.
2. **940 lines of dead code in mcp.zig (A2)**: Precisely mapped to 40+ functions across 3 clusters. Creates maintenance risk and cognitive overhead.
3. **Pipeline enrichment passes abort on OOM (A27)**: A memory spike during `runSimilarityPass` rolls back a successful extraction of thousands of files. The similarity pass is optional enrichment and should degrade gracefully.
4. **Zero test coverage for query_router (A3)**: The routing layer for all semantic queries is completely untested.

### What should be treated as debt

- **store.zig width (A11)**: Wide but not tangled. Split only if it keeps growing.
- **Manual JSON in query_router (A12)**: `std.json.fmt` handles escaping. The `properties_json` raw splice (A32) is the real fix needed, not a full migration.
- **Performance (A4, A5, A17, A22)**: Acceptable at current graph sizes.
- **Unresolved call tracking (A29)**: Would improve debuggability but doesn't affect correctness.
- **File hash content hashing (A28)**: Mtime+size is sufficient for most filesystems.

### Minimum high-leverage next actions

1. **Delete dead mcp.zig code** (1-2 hours). Removes 940 lines of confusion and unblocks clean wildcard dedup.
2. **Fix three Cypher correctness bugs** (half day). A18 (precedence), A19 (variable-length paths), A21 (ORDER BY). Eliminates silent wrong results.
3. **Wrap enrichment passes in catch** (30 min). A27 prevents OOM in optional passes from destroying successful extractions.
4. **Add query_router tests** (half day). A3 covers the untested routing layer.

These four actions address the highest-severity findings across correctness (Cypher), reliability (pipeline), and maintainability (dead code, test coverage).
