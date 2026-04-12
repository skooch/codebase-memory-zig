# codebase-memory-zig

This is a work in progress.

Zig port of [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp), an MCP server that builds a searchable knowledge graph from source code repositories.

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

## Project Layout

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
- [docs/zig-port-plan.md](docs/zig-port-plan.md) for the broader port roadmap
- [docs/gap-analysis.md](docs/gap-analysis.md) for parity and remaining gaps
- [docs/port-comparison.md](docs/port-comparison.md) for C-vs-Zig comparison notes

## Verification Notes

Typical local verification for behavior or build changes:

```sh
zig build
zig build test
zig fmt --check src/ build.zig
find src -name '*.zig' | zlint -S
```
