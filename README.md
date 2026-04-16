# codebase-memory-zig

Zig port of [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp), an MCP server that builds a searchable knowledge graph from source code repositories.

This is not a line-for-line translation. The Zig port restructures internals for better performance, cuts some features, introduces a hybrid serving architecture (FTS5 + graph + optional SCIP overlay), and ships tooling that the C original does not have.

**This project is not currently in a finished state, I'm still porting it. Please don't submit bugs just yet!**

## Some differences compared to the original

| Area | What Changed | Impact |
|------|-------------|--------|
| Cold indexing | 3.2x--8.2x faster across all benchmarked fixtures | Small repos index in ~13 ms vs ~48 ms; medium repos in ~1.4 s vs ~11.2 s |
| Free-text search | SQLite FTS5 virtual table with `unicode61` tokenizer | Prefix matching and token-aware ranking without spawning grep subprocesses |
| Query routing | `query_router.zig` dispatches each tool to the best substrate | FTS5 for `search_code`, graph for `trace_call_path`, SCIP for enrichment |
| SCIP sidecar | Optional `.codebase-memory/scip.json` import | Precise type/symbol metadata from language servers, without blocking baseline indexing |
| Graph queries | CTE pre-computation + batch BFS traversal | Fewer DB round-trips; replaces O(N * \|edges\|) correlated subqueries |
| JSON marshaling | `std.json` comptime struct reflection | ~1000 fewer LOC vs manual yyjson; new fields require only struct changes |
| Error safety | Error unions with `try`/`errdefer` | Missing error checks fail at compile time; transactional indexing prevents corrupt state |
| SQLite tuning | WAL journal, 64 MB mmap, `busy_timeout = 10s` | Better concurrent-access behavior and read throughput out of the box |

Benchmark data: [`.benchmark_reports/benchmark_report.md`](.benchmark_reports/benchmark_report.md) -- Details: [`docs/differentiators.md`](docs/differentiators.md)

## Port progress

The Zig port covers the daily-use MCP surface and core indexing pipeline. It is not yet a full feature-for-feature replacement for every C subsystem. Full details: [`docs/port-comparison.md`](docs/port-comparison.md)

| Area | Status | Notes |
|------|--------|-------|
| MCP tools (13 of 14) | Near parity | All tools except `ingest_traces` (stubbed in C too) |
| Core indexing (structure, definitions, imports, calls, usages, semantics) | Near parity | Parallel extraction, incremental reindex, transactional writes |
| Languages (Python, JavaScript, TypeScript, Rust, Zig) | Near parity | Tree-sitter-backed; heuristic fallback for other languages |
| Similarity detection (`SIMILAR_TO`) | Near parity | MinHash/LSH with tuned thresholds |
| Watcher / auto-reindex / runtime lifecycle | Near parity | Adaptive polling, persistent runtime DB, signal-driven shutdown |
| CLI install/uninstall/update (Codex CLI, Claude Code) | Near parity | 2 of the original's 10 agent targets |
| Route / cross-service graph | Partial | Verified graph-model fixture contract covers HTTP/async route callers, route nodes, handlers, route-linked data flow, and route summaries; broader framework expansion remains optional |
| LSP hybrid type resolution | Deferred | C has Go/C/C++ LSP-assisted paths |
| Git history / config linking passes | Near parity | Git change-coupling and verified config-link fixture slices are implemented; broader config-language/key-shape expansion remains optional |
| Graph UI | Cut | C ships an optional visualization server |
| Infra scanning (Docker, K8s, Terraform) | Cut | Outside project scope |

## Requirements

- Zig `0.15.2`
- SQLite is vendored in-repo
- tree-sitter support is vendored and wired through `build.zig`

Tool versions are managed with `mise`:

```sh
mise install
zig version
```

## Build

```sh
zig build
```

## Test

```sh
zig build test
```

## Run

Start the MCP server over stdio:

```sh
zig build run
```

Inspect CLI help and version:

```sh
zig build run -- --help
zig build run -- --version
```

Call a single CLI tool directly:

```sh
zig build run -- cli <tool> [json]
```

Cross-compile a target binary:

```sh
zig build -Dtarget=aarch64-linux-musl
```

Set an explicit build version:

```sh
zig build -Dversion=1.0.0
```

## Lint

Formatting is enforced with `zig fmt`:

```sh
zig fmt src/ build.zig
```

This repo also uses `zlint` for Zig source linting. Install the pinned release for your platform, put it on your `PATH`, then run:

```sh
find src -name '*.zig' | zlint -S
```

Pinned `zlint` release: `v0.7.9`

## Project layout

```text
src/
  root.zig          Module root, re-exports public API
  main.zig          CLI entry point + MCP server startup
  store.zig         SQLite graph store (nodes, edges, projects)
  graph_buffer.zig  In-memory graph buffer before SQLite persistence
  pipeline.zig      Multi-pass indexing pipeline orchestrator
  mcp.zig           MCP JSON-RPC server
  cypher.zig        Cypher query engine
  discover.zig      File discovery and gitignore handling
  watcher.zig       Auto-reindex watcher support
  registry.zig      Symbol and call-edge resolution
  minhash.zig       Near-clone fingerprinting
testdata/
  interop/          Cross-implementation interoperability fixtures
scripts/
  run_interop_alignment.sh  Compare Zig and C implementations
vendored/
  sqlite3/          Vendored SQLite amalgamation
  tree_sitter/      Vendored tree-sitter headers
  grammars/         Vendored parser grammars
```

## Docs

- [CLAUDE.md](CLAUDE.md) for agent-facing repo guidance
- [docs/differentiators.md](docs/differentiators.md) for where the Zig port is better than the C original
- [docs/port-comparison.md](docs/port-comparison.md) for full feature-by-feature parity tracking
- [docs/zig-port-plan.md](docs/zig-port-plan.md) for the broader port roadmap
- [docs/gap-analysis.md](docs/gap-analysis.md) for parity and remaining gaps

## Verification notes

Typical local verification for behavior or build changes:

```sh
zig build
zig build test
zig fmt --check src/ build.zig
find src -name '*.zig' | zlint -S
```
