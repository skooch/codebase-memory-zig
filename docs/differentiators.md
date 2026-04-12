# Zig Port Differentiators

Where `codebase-memory-zig` is architecturally or measurably better than the original C implementation (`codebase-memory-mcp`). This is not a parity tracker (see `port-comparison.md` for that) — it covers only areas where the Zig port adds something the C original does not have.

## Performance

Benchmarked on identical fixtures, same host (`swerve.local`, 2026-04-11). Both implementations produce 100% accuracy on all scored fixtures.

### Cold Indexing

| Repository | Zig (ms) | C (ms) | Speedup |
|------------|----------|--------|---------|
| python-basic | 12.9 | 46.7 | **3.6x** |
| javascript-basic | 11.7 | 51.3 | **4.4x** |
| typescript-basic | 14.0 | 51.2 | **3.7x** |
| rust-basic | 14.4 | 46.1 | **3.2x** |
| zig-basic | 15.3 | 48.5 | **3.2x** |
| codebase-memory-zig (medium, ~200 files) | 1,371 | 11,203 | **8.2x** |

### Query Latency (Small Repos)

Query latency is at parity on small repos (both ~12 ms median for `search_graph`, `query_graph`, `trace_call_path`). The Zig port uses slightly less RSS per query (~3.0 MB vs ~3.6 MB).

### search_code on Medium Repo

The FTS5-backed `search_code` path trades RSS for different latency characteristics on medium repos. On the `todo-search` scenario against this repo itself: Zig 413 ms / 28.8 MB RSS vs C 97 ms / 13.4 MB RSS. The tradeoff is that FTS5 enables richer lexical search capabilities that the C path does not have (see below).

Full benchmark data: `.benchmark_reports/benchmark_report.md`

## Architectural Differentiators

| Area | C Original | Zig Port | Why It Matters |
|------|-----------|----------|----------------|
| **Free-text search** | grep-based `search_code` | SQLite FTS5 virtual table with `unicode61` tokenizer (`search_index.zig`) | Enables prefix matching, token-aware ranking, and lexical candidate generation without spawning grep subprocesses |
| **Query routing** | Single graph-native serving path | `query_router.zig` dispatches each tool to the best internal substrate (FTS5, graph, SCIP, filesystem) | Tools can be individually optimized without changing the MCP contract |
| **SCIP sidecar overlay** | Not present | Optional `.codebase-memory/scip.json` import (`scip.zig`) adds precise type/symbol metadata from language servers | Enriches graph precision for languages without native parser support, without blocking baseline indexing |
| **Graph query optimization** | Correlated subqueries for node degree | CTE pre-computation via GROUP BY in `store.zig` replaces O(N * \|edges\|) degree lookups | Measurably faster on graphs with high edge counts |
| **Batch BFS traversal** | Per-node edge queries during trace | `findEdgesBySourceBatch()` / `findEdgesByTargetBatch()` process entire frontier levels in single SQLite round-trips | Fewer DB round-trips for deep or wide call chains |
| **JSON marshaling** | ~1000+ LOC of manual yyjson serialization | `std.json` with comptime struct reflection | Eliminates an entire class of serialization bugs; new fields require only struct changes |
| **Error handling** | `int` return codes, manually checked | Error unions (`!T`) with `try` / `errdefer` | Missing error checks fail at compile time, not at runtime |
| **Transactional indexing** | Manual error paths | `errdefer`-guarded `beginImmediate()` / `commit()` / `rollback()` in `pipeline.zig` | Corrupted intermediate graph state is structurally impossible |
| **Memory management** | Custom `CBMArena` + mimalloc global override | Zig `ArenaAllocator` per-file with stdlib GPA | No external allocator dependency; per-file arenas free entire extraction lifetime in one operation |
| **SQLite configuration** | Default pragmas | WAL journal, `mmap_size = 64 MB`, `synchronous = NORMAL`, `busy_timeout = 10s` compiled in | Better concurrent-access behavior and read throughput out of the box |

## Tooling the C Repo Does Not Ship

| Tool | What It Does | Location |
|------|-------------|----------|
| **Interop alignment harness** | Spins up both Zig and C as MCP servers, sends identical JSON-RPC sequences, canonicalizes and diffs outputs | `scripts/run_interop_alignment.sh` |
| **CLI parity harness** | Compares install/uninstall/update behavior in temp-HOME isolation | `scripts/run_cli_parity.sh` |
| **Benchmark suite** | Fixture-based accuracy scoring + latency + RSS measurement with JSON/Markdown reports | `scripts/run_benchmark_suite.sh` |
| **Agent comparison harness** | Task-scored agent-style comparison across test suites | `scripts/run_agent_comparison.zsh` |

## Simplifications vs. the C Original

Decisions from `docs/algorithm-audit.md` where the Zig port chose a simpler approach without losing meaningful capability:

| C Approach | Zig Replacement | Rationale |
|-----------|----------------|-----------|
| Direct SQLite page writer (1875 LOC) | Bulk `INSERT` with tuned pragmas | Simpler, sufficient throughput for the indexing pipeline |
| Slab allocator | `std.MemoryPool` / GPA | Idiomatic, less code, no external dependency |
| Louvain community clustering | Label propagation / directory-based grouping | Lighter weight, sufficient for architecture summaries |
| Full Cypher parser (3400 LOC) | Pattern-to-SQL template translator with pushdown | 95% query coverage with substantially less code |
| mimalloc global override | Zig GPA + `DebugAllocator` | Safer (double-free detection in debug), no vendored allocator |
| RSS-based memory budgeting | Fixed caps with clear errors | Simpler semantics for a dev tool |
