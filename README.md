# codebase-memory-zig

Zig port of [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp), an MCP server that builds a searchable knowledge graph from source repositories.

This is not a line-for-line translation. The Zig port keeps the original's daily-use MCP contract, restructures the internals around Zig + SQLite + tree-sitter, and deliberately narrows or cuts a few long-tail subsystems from the C project.

## Current State

The current target contract is complete. This repo is now best described as a usable, actively verified Zig implementation of the original's shared daily-use surface, not as an unfinished prototype.

What that means in practice:

| Area | Current state | Notes |
|------|---------------|-------|
| Shared MCP surface | Implemented | `13` meaningful tools are shipped; the original's `14th` tool, `ingest_traces`, is still a stub upstream and remains unimplemented here |
| Interop/parity harness | Green | Current recorded full compare: `33` fixtures, `251` comparisons, `0` mismatches, `cli_progress: match` |
| Core indexing pipeline | Strong shared parity for the chosen contract | Structure, definitions, imports, calls, usages, semantic hints, incremental indexing, watcher lifecycle, and similarity are all implemented |
| Language support | Broader than the original readiness floor | Parser-backed extraction covers Python, JavaScript, TypeScript, TSX, Rust, Zig, Go, Java, C#, PowerShell, and GDScript |
| Installer/productization | Broadly implemented | Shared Codex/Claude flows are parity-tested; detected-scope installer coverage now exercises the broader 10-agent matrix |
| Still intentionally narrower than C | Yes | No built-in UI server, no infra scanning pass family, no OTLP trace ingestion, and no claim of exhaustive Cypher/LSP parity |

Full comparison: [docs/port-comparison.md](docs/port-comparison.md)

## Compared To The Original

The biggest differences from the C project today are:

| Area | Zig port | Impact |
|------|----------|--------|
| Cold indexing | `3.2x` to `8.2x` faster on the measured fixtures | Faster first-index experience on small and medium repos |
| Free-text search | SQLite `FTS5` with `unicode61` tokenizer | Prefix matching and token-aware ranking without grep subprocesses |
| Query routing | `query_router.zig` dispatches to graph, FTS5, filesystem, or SCIP overlay paths | Each tool can use the best underlying substrate without changing the MCP contract |
| Sidecar enrichment | Optional `.codebase-memory/scip.json` import | Extra symbol/type precision without making baseline indexing depend on LSP |
| Graph execution | CTE pre-computation and batch BFS traversal | Fewer SQLite round-trips on dense graphs and deeper traces |
| Error handling | Zig error unions and `errdefer`-guarded transactions | Failures are harder to ignore and partial writes are easier to avoid |
| Tooling | Repo-owned interop, CLI parity, benchmark, soak, and security suites | Better ongoing evidence for compatibility and regressions |

Benchmark data: [`.benchmark_reports/benchmark_report.md`](.benchmark_reports/benchmark_report.md)
More detail: [docs/differentiators.md](docs/differentiators.md)

## Setup

Requirements:

- Zig `0.15.2`
- `mise` for tool installation
- vendored SQLite and tree-sitter sources in this repo

Install tools and fetch vendored grammars for a fresh checkout:

```sh
mise install
mise run bootstrap
```

If grammar sources are already present and you want to refresh them:

```sh
bash scripts/fetch_grammars.sh --force
```

`mise install` now bootstraps both `zig` and the pinned `zlint` binary used by this repo.

## Build And Run

Build:

```sh
zig build
```

Run tests:

```sh
zig build test
```

Run the stdio MCP server:

```sh
zig build run
```

Inspect CLI help and version:

```sh
zig build run -- --help
zig build run -- --version
```

Call a single tool directly:

```sh
zig build run -- cli <tool> [json]
```

Cross-compile or set an explicit version:

```sh
zig build -Dtarget=aarch64-linux-musl
zig build -Dversion=1.0.0
```

## Verification

Typical local verification for code changes:

```sh
zig build
zig build test
zig fmt --check src/ build.zig
mise run lint
```

If `zig build` reports missing vendored grammar sources, run `mise run bootstrap` and retry.

## Project Layout

```text
src/
  root.zig              Public module root
  main.zig              CLI entry point and stdio server startup
  mcp.zig               MCP JSON-RPC transport and tool handlers
  cli.zig               install/update/uninstall/config support
  pipeline.zig          Indexing orchestration
  extractor.zig         tree-sitter and line-based extraction
  store.zig             SQLite graph store
  graph_buffer.zig      In-memory graph build buffer
  cypher.zig            Cypher-like query support
  discover.zig          File discovery and language detection
  registry.zig          Symbol and call-edge resolution
  watcher.zig           Auto-reindex watcher
  runtime_lifecycle.zig Runtime DB lifecycle and startup/update behavior
  query_router.zig      Tool-to-substrate dispatch
  search_index.zig      FTS5-backed lexical search support
  scip.zig              Optional SCIP overlay import
  git_history.zig       Git coupling pass
  route_nodes.zig       Route/data-flow synthesis helpers
  adr.zig               ADR storage helpers
  minhash.zig           Similarity detection
testdata/
  interop/              Zig-vs-C and zig-only fixture corpus
scripts/
  run_interop_alignment.sh  Full Zig-vs-C MCP comparison
  run_cli_parity.sh         CLI/install parity harness
  run_benchmark_suite.sh    Benchmark and accuracy suite
  run_soak_suite.sh         Repeated runtime/index/query soak checks
  run_security_audit.sh     Static audit checks
vendored/
  sqlite3/              Vendored SQLite amalgamation
  tree_sitter/          Vendored tree-sitter headers
  grammars/             Vendored parser grammars
```

## Docs

- [CLAUDE.md](CLAUDE.md): repo-specific working rules
- [docs/port-comparison.md](docs/port-comparison.md): authoritative current comparison with the C original
- [docs/differentiators.md](docs/differentiators.md): places where the Zig port is better or simpler
- [docs/language-support.md](docs/language-support.md): language detection vs parser-backed extraction vs semantic parity
- [docs/install.md](docs/install.md): packaged install and release entrypoints
- [docs/installer-matrix.md](docs/installer-matrix.md): verified agent/config/install matrix
- [docs/gap-analysis.md](docs/gap-analysis.md): historical subsystem gap register, with a current snapshot at the top
- [docs/zig-port-plan.md](docs/zig-port-plan.md): completed plan history and architectural reference
