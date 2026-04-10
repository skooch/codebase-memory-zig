# Zig Port of codebase-memory-mcp

## Status: Readiness Gate Complete / Broader Port Still In Progress

### Current Snapshot

Completed now:
- The seven-phase interoperability-readiness plan is complete.
- The first-gate alignment slice is implemented for:
  - `index_repository`
  - `search_graph`
  - `query_graph`
  - `trace_call_path`
  - `list_projects`
- Parser-backed definition extraction is the default readiness path for:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
- The committed fixture corpus and harness currently report:
  - `Strict matches: 20`
  - `Diagnostic-only comparisons: 5`
  - `Mismatches: 0`

Still to implement after the readiness gate:
- Full MCP surface beyond the five readiness-scope tools.
- Full Cypher parser/executor parity beyond the constrained readiness query subset.
- Usage/type-ref parity and broader extraction semantics.
- Watcher-driven reindexing, incremental indexing, and broader CLI parity.
- Parallel indexing, MinHash/LSH, and the deferred enrichment/history features.

### Recommended Execution Order

The most effective next order is:

1. **Core graph/query substrate**
   - finish shared store, graph-buffer, traversal, schema, and registry/FQN primitives first
   - reason: these are reused by almost every remaining tool, so finishing them early reduces rework
2. **Low-risk MCP surface expansion**
   - add tools that mostly expose already-indexed data, such as snippet/schema/status/delete flows
   - reason: this increases usable surface area quickly without waiting on the hardest query/indexing work
3. **Indexing fidelity parity**
   - improve extraction, call/import resolution, usage/type-ref coverage, and semantic edges
   - reason: advanced tools are only as good as the graph they read from
4. **Heavy query and analysis features**
   - broaden `search_graph`, build fuller Cypher support, then add `search_code`, `get_architecture`, and `detect_changes`
   - reason: these depend on both stronger graph facts and stronger shared query infrastructure
5. **Runtime lifecycle and scale**
   - watcher, incremental indexing, parallel extraction, similarity
   - reason: lifecycle/concurrency work is much easier once single-threaded semantics are stable
6. **Productization and deferred features**
   - CLI parity, install/update/config flows, and selective promotion of deferred features
   - reason: user-facing packaging and long-tail features should settle after core runtime behavior stops shifting

---

## 1. Current Codebase Summary

| Metric | Value |
|--------|-------|
| Language | C11 (not Rust as initially assumed) |
| Source lines (src/) | ~35,700 |
| Internal extraction layer (internal/cbm/) | ~13,500 |
| Test lines | ~55,000 |
| Vendored deps | SQLite (266K LOC), Mongoose HTTP (29K), mimalloc, TRE regex, xxhash, yyjson |
| Tree-sitter grammars | 60+ languages (compiled C files in internal/cbm/) |
| Build system | GNU Make (Makefile.cbm) |

### Architecture

```
main.c
  |-- mcp/          MCP JSON-RPC server (stdio + HTTP UI)
  |-- pipeline/     Multi-pass indexing pipeline
  |     |-- pass_definitions   Tree-sitter extraction
  |     |-- pass_calls         Call resolution via registry
  |     |-- pass_usages        Usage/type ref edges
  |     |-- pass_semantic      Inherits/decorates/implements
  |     |-- pass_githistory    Git change coupling
  |     |-- pass_similarity    MinHash near-clone detection
  |     |-- pass_infrascan     Docker/K8s/Terraform parsing
  |     |-- pass_envscan       Env URL scanning
  |     |-- pass_configures    Config-code linking
  |     |-- pass_configlink    Config key normalization
  |     |-- pass_k8s           Kubernetes manifest nodes
  |     |-- pass_parallel      Thread pool orchestration
  |     |-- pass_tests         Test file/function tagging
  |     |-- pass_enrichment    Decorator tag enrichment
  |     |-- pass_route_nodes   HTTP route node creation
  |     |-- pass_compile_cmds  compile_commands.json parsing
  |     |-- pass_gitdiff       Git diff detection
  |     |-- pipeline_incremental  Incremental re-indexing
  |     |-- registry           Function name resolution
  |     `-- fqn                Qualified name computation
  |-- store/        SQLite graph database (nodes/edges/projects)
  |-- cypher/       Cypher query engine (lexer + parser + executor)
  |-- graph_buffer/ In-memory graph buffer (build then dump to SQLite)
  |-- discover/     File discovery, language detection, gitignore
  |-- watcher/      Adaptive polling for auto-reindex
  |-- cli/          Install/uninstall/update/config subcommands
  |-- traces/       OTLP trace processing
  |-- simhash/      MinHash fingerprinting + LSH
  |-- ui/           HTTP server (Mongoose) + 3D layout
  `-- foundation/   Arena, hash table, dyn_array, str_intern, logging,
                    platform compat, regex compat, YAML parser, vmem
```

---

## 2. Feature Triage: Port vs Cut

### MUST PORT (core value)

| Subsystem | LOC | Rationale |
|-----------|-----|-----------|
| **foundation/** (arena, hash_table, dyn_array, str_intern, str_util, log, platform, mem) | ~3,000 | Foundational data structures. Zig replaces most with stdlib (ArenaAllocator, std.HashMap, std.ArrayList, std.StringHashMap). Port = rewrite to idiomatic Zig. |
| **store/** | 4,527 | Core graph persistence. SQLite via `@cImport`. Clean API, well-tested. |
| **graph_buffer/** | 1,353 | In-memory indexing buffer. Core perf-critical path. |
| **pipeline/pipeline.c** | 798 | Orchestrator. Sequences passes, manages lifecycle. |
| **pipeline/pass_definitions** | (in internal/cbm) | Tree-sitter extraction. The heart of indexing. |
| **pipeline/pass_calls** | 571 | Call resolution. Core graph relationship. |
| **pipeline/pass_usages** | (in internal/cbm) | Usage edges. Core graph relationship. |
| **pipeline/pass_semantic** | 468 | Inheritance/interface edges. Core graph relationship. |
| **pipeline/pass_parallel** | 1,427 | Parallel extraction. Key for performance. |
| **pipeline/registry** | 598 | Function name resolution. Core for call edges. |
| **pipeline/fqn** | ~200 | Qualified name computation. |
| **mcp/** | 3,585 | MCP server. The entire external interface. |
| **cypher/** | 3,412 | Cypher query engine. Unique differentiator. |
| **discover/** | ~1,500 | File walk + language detection + gitignore. |
| **watcher/** | 463 | Auto-reindex on changes. |
| **cli/** | 3,496 | Install/uninstall/config. User-facing. |
| **internal/cbm extraction** | ~8,000 | Tree-sitter extraction (defs, calls, imports, usages, semantic). The core extraction engine. |
| **simhash/minhash** | 505 | MinHash near-clone detection. Recent, well-implemented. |

### CUT (do not port)

| Subsystem | LOC | Rationale |
|-----------|-----|-----------|
| **traces/** | 142 | OTLP trace ingestion. The MCP handler is a **stub** that says "not yet implemented". Zero working functionality. Dead feature. |
| **pipeline/pass_infrascan** | 1,229 | Monolithic mess: parses Dockerfiles, Compose, CloudBuild, .env, shell scripts, Terraform in one file. The individual parser functions (`cbm_parse_dockerfile_source`, `cbm_parse_dotenv_source`, `cbm_parse_shell_source`, `cbm_parse_terraform_source`) are **declared but have no callers** - dead code. The pass itself duplicates extraction layer functionality for infra files. |
| **pipeline/pass_envscan** | 426 | Scans for env URLs. Niche, low-value feature that walks filesystem redundantly. |
| **pipeline/pass_k8s** | 242 | Only parses first YAML document (multi-doc unsupported). Pipeline marks it `ignore_err = true`. Half-baked. |
| **pipeline/pass_compile_commands** | 285 | Parses compile_commands.json for C/C++ include paths. Niche feature with narrow applicability. |
| **pipeline/pass_configures** | 131 | Env var name detection. Tiny, low-value. |
| **ui/** (http_server, layout3d, config, embedded_stub) | ~1,900 | Entire HTTP UI subsystem. Uses vendored Mongoose. The embedded_stub.c means standard builds serve nothing. Separate concern that should be a separate project/tool if desired. |
| **foundation/yaml.c** | ~400 | Hand-rolled YAML parser for K8s pass (which we're cutting). |
| **foundation/compat_regex** | ~200 | Windows regex compat using vendored TRE. Zig's stdlib or PCRE via @cImport replaces this. |
| **foundation/vmem** | ~200 | Virtual memory allocator, already superseded by mem.c + mimalloc. Legacy. |
| **internal/cbm/lz4_store** | ~100 | LZ4 compression. Unclear if still used. |
| **internal/cbm/preprocessor.cpp** | 95 | C++ file in a C project. Preprocessor for C/C++ extraction. |

### DEFER (port later if needed)

| Subsystem | LOC | Rationale |
|-----------|-----|-----------|
| **pipeline/pass_githistory** | 514 | Git change coupling. Nice feature, but optional for v1. Adds libgit2 dependency complexity. |
| **pipeline/pass_enrichment** | ~200 | Decorator tag enrichment. Polish feature, not core. |
| **pipeline/pass_route_nodes** | 742 | HTTP route node creation. Useful but complex, can come after core works. |
| **pipeline/pass_configlink** | ~200 | Config-code linking. Polish feature. |
| **pipeline/pass_tests** | 285 | Test file tagging. Nice metadata, not core. |
| **pipeline/pipeline_incremental** | ~400 | Incremental re-indexing. Important for perf, but full re-index works first. |
| **internal/cbm/lsp/** | ~2,000 | LSP integration for C and Go. Advanced feature, not core. |

---

## 3. Vendored Dependencies: Zig Mapping

| Current (C) | Zig Approach | Notes |
|-------------|-------------|-------|
| **SQLite (vendored amalgamation)** | `@cImport("sqlite3.h")` + compile `sqlite3.c` in build.zig | Proven path. Keep vendored amalgamation. |
| **tree-sitter runtime** | `tree-sitter/zig-tree-sitter` package or `@cImport` | Official Zig bindings exist (0.26.0). |
| **tree-sitter grammars (60+ .c files)** | Compile as C sources in build.zig | Same approach, Zig build system handles C natively. |
| **yyjson** | `std.json` | Zig's stdlib JSON is good. Comptime struct reflection replaces manual parsing. |
| **xxhash** | `std.hash.XxHash64` or `@cImport` | Zig stdlib has xxhash. |
| **mimalloc** | `std.heap.DebugAllocator` (dev) / `std.heap.page_allocator` (prod) | Zig's allocator model replaces global malloc override. Per-subsystem allocators give better control. |
| **Mongoose** | CUT (UI is cut) | Not needed. |
| **TRE regex** | CUT | Zig can use PCRE2 via `@cImport` or `std.mem` pattern matching for simple cases. For Cypher regex: compile PCRE2 as C dep. |

---

## 4. Zig Architecture Decisions

### 4.1 Memory Model

The C codebase already uses **arena allocation** (`CBMArena`) and **explicit allocation** patterns. This maps directly to Zig:

| C Pattern | Zig Equivalent |
|-----------|---------------|
| `CBMArena` (per-file extraction) | `std.heap.ArenaAllocator` with per-file lifetime |
| `cbm_ht_create()` / `CBMHashTable` | `std.StringHashMap(T)` or `std.AutoHashMap` |
| `CBM_DYN_ARRAY(T)` macro | `std.ArrayList(T)` |
| `cbm_str_intern()` | `std.StringHashMap(void)` on arena |
| `malloc/free` for long-lived data | `std.heap.GeneralPurposeAllocator` (debug) / `std.heap.c_allocator` (release) |
| `cbm_mem_init()` / RSS tracking | Custom allocator wrapping page_allocator with budget tracking |

### 4.2 Error Handling

| C Pattern | Zig Equivalent |
|-----------|---------------|
| `int` return codes (0 = OK, -1 = ERR) | Error unions: `fn foo() !ResultType` |
| `CBM_STORE_OK`, `CBM_STORE_ERR`, `CBM_STORE_NOT_FOUND` | `error{StoreError, NotFound}` error set |
| `cbm_store_error()` last-error string | Diagnostic sink: store error context in struct, return error code |
| `if (!p) return -1;` null checks | `orelse return error.AllocationFailed` |

### 4.3 Polymorphism

| C Pattern | Zig Equivalent |
|-----------|---------------|
| Function pointers (e.g. `cbm_index_fn`) | `*const fn(...)` function pointers OR comptime generics |
| Opaque handles (`cbm_store_t *`) | Opaque structs with methods |
| Pipeline pass function table | Tagged union of pass types OR comptime-generated dispatch |
| `CBMLanguage` enum + switch | `enum` + comptime `switch` (exhaustive) |

### 4.4 Concurrency

The current C codebase uses **pthreads** (via `compat_thread.h`). Zig equivalent:

| C Pattern | Zig Equivalent |
|-----------|---------------|
| `cbm_thread_create()` | `std.Thread.spawn()` |
| `cbm_mutex_lock()` | `std.Thread.Mutex` |
| Worker pool (pass_parallel.c) | `std.Thread.Pool` or custom pool with `std.Thread` |
| `atomic_int` for cancellation | `std.atomic.Value(i32)` |
| Watcher polling loop | `std.Thread.sleep()` + poll loop |

### 4.5 Serialization (MCP protocol)

Replace hand-rolled yyjson JSON manipulation with Zig struct-based serialization:

```zig
const McpRequest = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    id: ?i64 = null,
    params: ?std.json.Value = null,
};

// Parse: std.json.parseFromSlice(McpRequest, allocator, line, .{})
// Emit: std.json.stringify(response, .{}, writer)
```

This eliminates ~500 lines of manual JSON string building in mcp.c.

### 4.6 Interoperability Readiness Slice

For the first alignment milestone, we scope parity checks to:

- Tool surface: `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, `list_projects`.
- Language extraction slice: Rust, Zig, Python, JavaScript/TypeScript.
- Graph comparison scope: `nodes`, `edges`, and traversal around `CALLS`/`CONTAINS`/`IMPLEMENTS`/`INHERITS`.
- Deterministic behavior:
- Stable ordering in query/list responses.
- Path normalization to `/` in serialized output.
- No requirement for internal IDs or deferred feature-specific metadata.
- Index/list summary counts are retained in the baseline report but are diagnostic only for the first gate; they do not gate readiness once the behavioral assertions pass.

### 4.7 Alignment Comparison Contract (Readiness Gate)

This section defines how outputs are compared while building the first interoperability baseline.

- Normalize project and file paths by converting all separators to `/`, then trimming trailing `/`.
- Ignore internal numeric IDs and process-order noise (`id` fields on nodes and traversal edges) when comparing outputs.
- Compare results with explicit stable order rules:
  - `search_graph`: order by `name`, then `file_path`, then `qualified_name` (when equal).
  - `query_graph`: compare `columns` + `rows` order exactly as returned by the query.
  - `trace_call_path`: compare `edges` as an unordered set unless contract explicitly states order.
  - `list_projects`: sort by `name`.
- Treat metadata from CUT and DEFER systems as non-blocking by default:
  - watcher callbacks/index-status side effects,
  - unused MCP tools,
  - optional enrichment fields not emitted by the readiness slice.

#### Tool contracts

- `index_repository(project_path, mode)`:
  - **Required response fields:** `project`, `mode`, `nodes`, `edges`.
  - **Acceptance:** counts (`nodes`, `edges`) must be numeric and non-negative. The first gate logs these counts for comparison, but they are not a blocking comparison field once the tool succeeds and the fixture minimums are met.

- `search_graph(project, filters)`:
  - **Required response fields:** `nodes[]` where each node includes:
    - `label`, `name`, `qualified_name`, `file_path`.
  - **Ignored fields:** `id`.
  - **Acceptance:** rows for the fixture's required symbols must exist after normalization. Extra rows are tolerated unless they indicate wrong label/filter behavior or another hard-fail field contract break.

- `query_graph(project, query, max_rows)`:
  - **Required response fields:** `columns[]`, `rows[][]`.
  - **Acceptance:** schema shape, column order, and ordered row payloads must match normalized expected output.
  - **String normalization:** quote escaping and whitespace should be normalized before deep comparison.
  - **Aggregate normalization:** count-style column aliases such as `count` and `COUNT(n)` normalize to `count` for first-gate fixture comparisons.

- `trace_call_path(project, start_node_qn, direction, depth)`:
  - **Required response fields:** `edges[]` with `source`, `target`, `type`.
  - **Accepted behavior now:** the current Zig implementation traverses all edge types; this is intentional for the first pass and treated as contract-compliant as long as edge direction/depth behavior is equivalent.
  - **Ignored fields:** `id` values inside edges.
  - **Acceptance:** deterministic traversal result for same graph snapshot and parameters. For the fixture gate, required edge types must be present; extra traversed edges are tolerated when direction/depth semantics still match.

- `list_projects()`:
  - **Required response fields:** each entry must include `name`, `indexed_at`, `root_path`, `nodes`, `edges`.
  - **Acceptance:** same project list and normalized `root_path` values, stable by name. `nodes`/`edges` are retained as diagnostic baseline data rather than hard comparison fields.

### 4.8 Parser Definition Extraction Status

- For readiness scope languages, definitions come from tree-sitter by default:
  - `.python`
  - `.javascript`
  - `.typescript`
  - `.tsx`
  - `.rust`
  - `.zig`
- For all other languages, the extractor continues to use existing heuristic parsing for symbol extraction only.
- Current intentional parser limitations (accepted as deferred for phase-2 scope):
  - member-call and generic edge inference remain best effort; call candidates are still collected textually after definition extraction.
  - import normalization is still heuristic and may not infer package-local aliasing exactly as original.
  - semantic edges rely on name matching and are expected to be incomplete for complex inheritance/trait patterns.

### Exclusions in scope

- **CUT features**: do not block alignment until promoted.
- **DEFER features**: do not block alignment.
- `watcher` auto-index behavior is deferred for the initial readiness gate.

### 4.8 Build System

```zig
// build.zig sketch
const exe = b.addExecutable(.{ .name = "cbm", .root_source_file = b.path("src/main.zig") });

// SQLite vendored
exe.addCSourceFile(.{ .file = b.path("vendored/sqlite3/sqlite3.c"), .flags = &.{
    "-DSQLITE_THREADSAFE=1", "-DSQLITE_OMIT_LOAD_EXTENSION=1",
}});

// Tree-sitter runtime
exe.addCSourceFile(.{ .file = b.path("vendored/ts_runtime/lib/src/lib.c") });

// Tree-sitter grammars (60+ languages)
for (grammar_sources) |src| {
    exe.addCSourceFile(.{ .file = b.path(src) });
}

exe.linkLibC();
```

Cross-compilation to Linux/Windows/macOS comes free.

---

## 5. Sequenced Milestones

### M0: Skeleton + Foundation (Week 1-2)
- `build.zig` that compiles SQLite + tree-sitter runtime + one grammar
- Foundation types: allocator wrappers, string interning, logging
- Port `store/` to Zig calling SQLite via `@cImport`
- Port `graph_buffer/` using `std.HashMap` + `std.ArrayList`
- Tests: store CRUD, graph buffer ops

**Exit criterion:** Can create a store, insert nodes/edges, query them.

### M1: Extraction Pipeline (Week 3-5)
- Port `discover/` (file walk, language detection, gitignore)
- Port extraction layer: tree-sitter parsing, definition extraction
- Port `pipeline/` orchestrator with pass_definitions + registry
- Port pass_calls, pass_usages, pass_semantic
- Single-threaded first

**Exit criterion:** Can index a small repo (e.g., itself) and produce a populated graph DB.

### M2: Query Layer (Week 5-7)
- Port `cypher/` lexer + parser + executor
- Port `mcp/` JSON-RPC server (stdio transport)
- Wire up all MCP tools: search_graph, query_graph, get_code_snippet, trace_call_path, etc.
- Port `watcher/` for auto-reindex

**Exit criterion:** Can run as MCP server, index a repo, answer queries via Claude Code.

### M3: Performance + CLI (Week 7-9)
- Port parallel extraction (pass_parallel) using `std.Thread.Pool`
- Port MinHash similarity detection
- Port CLI subcommands (install, uninstall, update, config)
- Memory budget tracking
- Port FQN computation

**Exit criterion:** Performance parity with C version on a large repo. CLI works.

### M4: Polish + Deferred Features (Week 9+)
- Incremental re-indexing
- Git history pass (change coupling)
- Route node creation
- Test tagging
- Config-code linking
- Decorator enrichment

---

## 6. Risks and Open Decisions

### Decisions Needed

1. **Tree-sitter binding approach:** Use official `zig-tree-sitter` package (cleaner, but adds dependency management) or raw `@cImport` on vendored tree-sitter C code (simpler build, full control)?

2. **Grammar compilation strategy:** The 60+ tree-sitter grammar .c files are each ~1-100KB. Compile all into one binary (large but simple) or lazy-load as shared libraries (complex but smaller binary)?

3. **Regex engine for Cypher:** The Cypher executor uses regex matching (`=~` operator). Options: (a) PCRE2 via `@cImport`, (b) Zig-native regex library, (c) implement minimal regex matching. Current C code uses POSIX `<regex.h>`.

4. **MCP transport:** Stdio only for v1 (matching current primary use), or also HTTP+SSE (Streamable HTTP) from the start?

5. **Minimum Zig version:** Target 0.14.x (current stable) or 0.15.x (has serde.zig, newer features)? 0.16 will bring the new async Io but isn't stable yet.

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Tree-sitter grammar .c files may not compile cleanly with Zig's C compiler | Medium | Test early (M0). Zig's C compiler is Clang-based, same as current macOS builds. |
| `@cImport` may fail on complex tree-sitter macros | Low | Fall back to manual Zig bindings for specific types. Tree-sitter API is small. |
| No production async in Zig 0.14 | Low | MCP stdio is synchronous. Thread pool suffices for parallelism. |
| Zig 0.14 → 0.15 breaking changes | Medium | Pin to one version. Zig's semver guarantees nothing pre-1.0. |
| Loss of mimalloc performance | Low | Zig's page allocator + arena pattern may actually be faster for this workload (batch alloc/free). Benchmark in M3. |
| Cypher regex without POSIX `<regex.h>` on Windows | Medium | Vendor PCRE2 (small, C library, compiles with Zig). |

### What C-to-Zig Buys You

- **Cross-compilation for free**: Linux, macOS, Windows from any host. Currently requires per-platform CI.
- **Safer memory management**: DebugAllocator catches use-after-free, leaks at runtime (vs. relying on ASan CI builds today).
- **Cleaner build**: Single `build.zig` replaces 400-line Makefile with platform-specific conditionals.
- **Better JSON handling**: `std.json` with comptime struct reflection replaces ~500 lines of manual yyjson manipulation.
- **Elimination of vendored deps**: mimalloc, yyjson, xxhash all replaced by Zig stdlib. Mongoose eliminated (UI cut).
- **Test integration**: `zig build test` replaces the current test harness + Makefile targets.

### What You Lose

- **Compile-time memory safety**: Zig has no borrow checker. Runtime DebugAllocator is the safety net.
- **Ecosystem maturity**: Fewer libraries, less battle-tested tooling.
- **Stable ABI story**: Zig pre-1.0 means language changes between versions.
- **mimalloc's performance tuning**: Would need benchmarking to verify Zig allocators match.

---

## 7. Lines of Code Estimate

| Component | C LOC (current) | Zig LOC (estimated) | Notes |
|-----------|-----------------|---------------------|-------|
| Foundation | 3,000 | ~500 | Mostly replaced by stdlib |
| Store | 4,527 | ~3,500 | Similar, cleaner with error unions |
| Graph buffer | 1,353 | ~1,000 | std.HashMap replaces custom hash table |
| Pipeline core | 2,000 | ~1,500 | Cleaner pass orchestration |
| Extraction | 8,000 | ~7,000 | Mostly tree-sitter API calls, similar |
| MCP | 3,585 | ~2,000 | std.json eliminates manual JSON |
| Cypher | 3,412 | ~3,000 | Parser complexity is inherent |
| Discover | 1,500 | ~1,000 | std.fs replaces platform compat |
| Watcher | 463 | ~400 | Nearly 1:1 |
| CLI | 3,496 | ~2,500 | Cleaner arg parsing |
| SimHash | 505 | ~400 | Nearly 1:1 |
| Registry | 598 | ~400 | std.HashMap simplifies |
| Build system | 400 (Makefile) | ~200 (build.zig) | Dramatically simpler |
| **Total** | **~33,000** | **~23,000** | **~30% reduction** |

The reduction comes primarily from: stdlib replacing foundation layer, std.json replacing manual JSON manipulation, and cutting ~4,000 LOC of dead/half-baked features.

---

## 8. Plan Checklist

Checked means complete relative to this plan's stated goal. Unchecked means still incomplete even if there is useful scaffolding or partial work in the repo.

### M0 Checklist

- [x] `build.zig` compiles SQLite + tree-sitter runtime + one grammar
- [ ] Foundation types: allocator wrappers, string interning, logging
- [x] Port `store/` to Zig calling SQLite via `@cImport`
- [x] Port `graph_buffer/` using `std.HashMap` + `std.ArrayList`
- [x] Tests: store CRUD, graph buffer ops
- [x] Exit criterion: can create a store, insert nodes/edges, query them

### M1 Checklist

- [x] Port `discover/` (file walk, language detection, gitignore)
- [x] Port extraction layer: tree-sitter parsing, definition extraction
- [x] Port `pipeline/` orchestrator with `pass_definitions` + `registry`
- [ ] Port `pass_calls`, `pass_usages`, `pass_semantic`
- [x] Single-threaded first
- [x] Exit criterion: can index a small repo and produce a populated graph DB
Current state: the end-to-end vertical slice is working with parser-backed definitions plus persisted call/import/semantic edges for readiness-scope languages, but full `pass_usages` parity and broader extraction parity remain outstanding.

### M2 Checklist

- [ ] Port `cypher/` lexer + parser + executor
- [x] Port `mcp/` JSON-RPC server (stdio transport)
- [ ] Wire up all MCP tools: `search_graph`, `query_graph`, `get_code_snippet`, `trace_call_path`, etc.
- [ ] Port `watcher/` for auto-reindex
- [ ] Exit criterion: can run as MCP server, index a repo, answer queries via Claude Code
Current state: the readiness-slice MCP surface is live and under harness coverage for `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`, but the broader tool surface, watcher integration, and fuller query semantics are still incomplete.

### M3 Checklist

- [ ] Port parallel extraction (`pass_parallel`) using `std.Thread.Pool`
- [ ] Port MinHash similarity detection
- [ ] Port CLI subcommands (`install`, `uninstall`, `update`, `config`)
- [ ] Memory budget tracking
- [ ] Port FQN computation
- [ ] Exit criterion: performance parity with C version on a large repo, CLI works

### M4 Checklist

- [ ] Incremental re-indexing
- [ ] Git history pass (change coupling)
- [ ] Route node creation
- [ ] Test tagging
- [ ] Config-code linking
- [ ] Decorator enrichment

## Completion Summary

Complete plan/milestone slices:
- Interoperability-readiness Phases 1-7
- M0 exit criterion
- M1 exit criterion for a single-threaded readiness slice
- M2 readiness subset only

Still-open implementation slices:
- Remaining M2 work:
  - full Cypher support
  - remaining MCP tools
  - watcher-based auto-reindex
- All of M3:
  - parallel extraction
  - MinHash similarity integration
  - CLI parity
  - memory/performance parity work
- All of M4:
  - incremental/history/enrichment features

## 9. Post-Readiness Execution Plan

The tracked plan for the next stage of work now lives at:

- [post-readiness-zig-port-execution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/post-readiness-zig-port-execution-plan.md)
- [post-readiness-zig-port-execution-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/post-readiness-zig-port-execution-progress.md)

That plan replaces the older assumption that the remaining work should simply proceed M2 -> M3 -> M4 as written. The new sequencing is dependency-driven and should reduce churn while still delivering useful public-surface growth early.
