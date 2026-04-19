# codebase-memory-zig

Zig port of [codebase-memory-mcp](../codebase-memory-mcp) — an MCP server that builds knowledge graphs from codebases.

## Setup

After first clone, fetch vendored tree-sitter grammars:

```sh
bash scripts/fetch_grammars.sh        # idempotent, skips if already present
bash scripts/fetch_grammars.sh --force # re-fetch from upstream
```

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
- `zlint` is not bootstrapped by `mise` in this repo today; check `command -v zlint` before relying on that lint command, and if it is missing report the verification as blocked instead of treating it as a source failure.
- If MCP stdio starts acknowledging only the first request in a piped session, treat `src/mcp.zig` `runFiles` framing as suspect first; this repo has already tripped over `std.Io.Reader.takeDelimiterExclusive` there, and the durable fix is an explicit newline-framed file read loop.
- If `zig build` appears to leave `zig-out/bin/cbm` on stale behavior after a `src/main.zig` edit, verify the executable with a fresh `--cache-dir` / `--global-cache-dir` / `--prefix` build. A stale installed binary can mask a compile error in the executable step even when an older `zig-out/bin/cbm` is still present. Also avoid importing `discover.zig` directly from `src/main.zig`; use `cbm.discover` there so test builds do not trip Zig's duplicate-module error.
- If `zig build` or `zig build test` fails with `NoSpaceLeft`, check `df -h . /Users/skooch/.cache/zig` first. The worktree-local `.zig-cache` can grow large enough to exhaust the shared Data volume; remove `.zig-cache` in the affected worktree and retry before treating it as a source failure.
- If `git commit` or `git add` fails because `.git/index.lock` already exists, treat it as a stale lock, remove it with a non-interactive `rm -f .git/index.lock`, and retry the git command.
- Keep `scripts/run_interop_alignment.sh` inline Python compatible with the system `python3` here (currently 3.9); avoid `X | Y` type-union syntax in that heredoc or the parity harness will fail before running comparisons.
- From peer worktrees under `../worktrees/`, the original C repo is not at `../codebase-memory-mcp`; script defaults that compare against the C binary need a `../../codebase-memory-mcp` fallback or explicit override so interop/benchmark runs do not fail on path resolution alone.
- `scripts/run_benchmark_suite.sh` runs with `set -u`; if you forward optional trailing args, guard the empty-array case instead of unconditionally expanding `${EXTRA_ARGS[@]}` or the script will fail before the Python harness starts.
- Fresh worktrees may not include the untracked `vendored/grammars/` and `vendored/tree_sitter/` directories required by `zig build test`; if the build fails with missing `vendored/grammars/*/parser.c`, run `bash scripts/bootstrap_worktree.sh [primary-checkout]` or copy those vendored directories from the primary checkout into the worktree before retrying verification.
- If `bash scripts/bootstrap_worktree.sh` prints success but `zig build` still fails on missing `vendored/grammars/*/parser.c`, check for a partially populated `vendored/grammars/` directory in the worktree. The bootstrap script must copy missing grammar subdirectories, not just skip work because the top-level directory already exists.
- If `zig build` fails after adding a vendored grammar with errors like `unknown type name 'TSFieldMapSlice'`, check whether that grammar's local `tree_sitter/` header directory was copied alongside `parser.c`. Existing grammars here rely on grammar-local headers first; copy `vendored/grammars/<lang>/tree_sitter/` before changing the shared `vendored/tree_sitter/` headers.
- The agent comparison harness is intentionally `zsh`-only via `scripts/run_agent_comparison.zsh`; keep that entrypoint canonical instead of reintroducing a shell-compat wrapper.
- The system `bash` on this macOS host is `3.2`, so helper scripts must not rely on associative arrays. If `scripts/fetch_grammars.sh` fails at `declare -A` with `set -u`, rewrite the mapping layer with portable `case` helpers before retrying.

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
