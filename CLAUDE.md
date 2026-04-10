# codebase-memory-zig

Zig port of [codebase-memory-mcp](../codebase-memory-mcp) — an MCP server that builds knowledge graphs from codebases.

## Build

```sh
zig build              # compile
zig build test         # run unit tests
zig build run          # run MCP server (stdio)
zig build run -- --version
zig build run -- --help
zig build run -- cli <tool> [json]
```

Cross-compile: `zig build -Dtarget=aarch64-linux-musl`
Set version: `zig build -Dversion=1.0.0`

## Architecture

```
src/
  root.zig          Module root, re-exports public API
  main.zig          CLI entry point + MCP server startup
  store.zig         SQLite graph store (nodes/edges/projects)
  graph_buffer.zig  In-memory graph buffer (build then dump to SQLite)
  pipeline.zig      Multi-pass indexing pipeline orchestrator
  mcp.zig           MCP JSON-RPC server (stdio + HTTP)
  cypher.zig        Cypher query engine (lexer/parser/executor)
  discover.zig      File discovery, language detection, gitignore
  watcher.zig       Adaptive polling for auto-reindex
  registry.zig      Function name resolution for call edges
  minhash.zig       MinHash fingerprinting for near-clone detection
```

## Dependencies

- **SQLite**: vendored amalgamation in `vendored/sqlite3/`, compiled as C via build.zig
- **tree-sitter**: via `zig-tree-sitter` package (build.zig.zon)
- **std.json**: stdlib JSON for MCP protocol (no external JSON lib)

## Conventions

- Zig 0.15.x (minimum 0.15.2)
- Explicit allocator passing everywhere
- `std.heap.DebugAllocator` in debug, consider `std.heap.c_allocator` for release
- Arena allocators for per-file extraction lifetimes
- Error unions with inferred error sets where possible
- Tests live in `*_test.zig` files alongside their module
- `zig fmt` for formatting (enforced)
- `find src -name '*.zig' | zlint -S` for Zig lint checks
- If `git commit` or `git add` fails because `.git/index.lock` already exists, treat it as a stale lock, remove it with a non-interactive `rm -f .git/index.lock`, and retry the git command.

## Porting from C

The original C codebase lives at `../codebase-memory-mcp`. Key mappings:

| C | Zig |
|---|-----|
| `CBMArena` | `std.heap.ArenaAllocator` |
| `CBMHashTable` | `std.StringHashMap(T)` |
| `CBM_DYN_ARRAY(T)` | `std.ArrayList(T)` |
| `cbm_str_intern()` | `std.StringHashMap(void)` on arena |
| yyjson manual JSON | `std.json` with struct reflection |
| `int` return codes | Error unions: `!T` |
| Function pointers + `void*` | `*const fn(...)` or comptime generics |
| pthreads | `std.Thread` + `std.Thread.Pool` |

## What was cut from C version

These features are NOT being ported (dead code or half-baked):
- `traces/` (ingest_traces stub, never implemented)
- `pass_infrascan` (dead parser functions, monolithic)
- `pass_envscan`, `pass_k8s` (half-baked, errors silently ignored)
- `pass_compile_commands`, `pass_configures` (niche, low-value)
- `ui/` HTTP server (Mongoose, separate concern)
- `foundation/yaml.c`, `compat_regex`, `vmem` (superseded by Zig stdlib)
