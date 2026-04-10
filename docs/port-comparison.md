# Port Comparison: `codebase-memory-zig` vs `codebase-memory-mcp`

## Purpose

This document is a source-backed comparison of the current Zig port against the original C implementation.

It is intentionally not a wish list. It describes:

- what the original C project ships today
- what the Zig port ships today
- where the Zig port is near-parity for the current target contract
- where the Zig port is intentionally narrower, deferred, or not ported

## Sources Used

- Planning and status docs in this repo:
  - `docs/zig-port-plan.md`
  - `docs/gap-analysis.md`
  - `docs/plans/implemented/interoperability-alignment-readiness-plan.md`
  - `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`
- Zig implementation:
  - `src/main.zig`
  - `src/mcp.zig`
  - `src/pipeline.zig`
  - `src/extractor.zig`
  - `src/discover.zig`
  - `src/watcher.zig`
  - `src/minhash.zig`
  - `src/cli.zig`
- Original C implementation:
  - `../codebase-memory-mcp/README.md`
  - `../codebase-memory-mcp/src/main.c`
  - `../codebase-memory-mcp/src/mcp/mcp.c`
  - `../codebase-memory-mcp/src/pipeline/pipeline.h`
  - `../codebase-memory-mcp/src/store/store.c`
  - `../codebase-memory-mcp/src/discover/language.c`
  - `../codebase-memory-mcp/src/cli/cli.c`
  - `../codebase-memory-mcp/src/cli/progress_sink.c`

## Status Legend

| Status | Meaning |
|--------|---------|
| `Near parity` | Implemented strongly enough to cover the current daily-use target contract with only minor contract differences. |
| `Partial` | Implemented, but materially narrower than the original in behavior, scope, or output richness. |
| `Deferred` | Intentionally left out of the completed target contract and tracked as optional future work. |
| `Cut` | Intentionally not ported. |
| `N/A` | The original feature is itself stubbed or not a meaningful parity target. |

## Executive Summary

| Area | Original C | Zig Port | Status |
|------|------------|----------|--------|
| Readiness/interoperability gate | Full first-gate reference implementation | Full first-gate parity gate completed, automated, and passing | `Near parity` |
| Daily-use MCP surface | Full 14-tool surface, though `ingest_traces` is stubbed | Complete current-target daily-use surface, but without `manage_adr` and `ingest_traces` | `Partial` |
| Core indexing pipeline | Broad multi-pass pipeline including routes, tests, config links, infra scans, git history, similarity | Strong core pipeline for structure, definitions, imports, calls, usages, semantics, incremental, parallel, similarity | `Partial` |
| Runtime lifecycle | Watcher, auto-index, update notifications, UI-capable runtime | Watcher, auto-index, incremental, transactional indexing, persistent runtime DB | `Near parity` |
| CLI/productization | Rich install/update/config for 10 agents plus hooks/instructions | Source-build-friendly install/update/config for Codex CLI and Claude Code | `Partial` |
| Optional/long-tail systems | UI, route graph, ADR, infra/resource indexing, git history, tests, config linking | Explicitly deferred or cut | `Deferred` / `Cut` |

## 1. Project Scope and Product Shape

| Capability | Original C (`codebase-memory-mcp`) | Zig Port (`codebase-memory-zig`) | Status | Notes |
|-----------|-------------------------------------|----------------------------------|--------|-------|
| Stated product goal | Full-featured code intelligence engine with 14 MCP tools, UI variant, 66 languages, 10-agent install path | Interoperable, higher-performance and more reliable daily-use port of the original | `Partial` | The Zig repo explicitly treats completion of Phase 7 as completion of the current target contract, not exhaustive parity. |
| Readiness gate | Reference side of the interop harness | Completed and passing: `Strict matches: 20`, `Diagnostic-only comparisons: 5`, `Mismatches: 0` | `Near parity` | This is the strongest parity claim in the Zig repo and is fully documented. |
| Broader post-readiness target | Everything in the original project | Current target contract only; long-tail parity moved to deferred backlog | `Partial` | See `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`. |
| Built-in graph UI | Yes, optional UI binary / HTTP server | No | `Cut` | Original has `src/ui/*` and `--ui` flags. Zig intentionally does not port the UI. |
| Release/install packaging | Prebuilt release artifacts plus setup scripts and install scripts | Source-build oriented repo with `zig build`; no release/install script set in the Zig repo | `Partial` | The Zig repo has a working CLI installer layer but not the original’s packaging/distribution surface. |

## 2. MCP Protocol and Tool Surface

### 2.1 Protocol Layer

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| `initialize` | Yes | Yes | `Near parity` | Both serve stdio JSON-RPC MCP. |
| `tools/list` | Yes, advertises 14 tools | Yes, currently advertises 12 implemented tools | `Partial` | Zig declares `manage_adr` and `ingest_traces` in `Tool`, but does not expose them in `tools/list`. |
| `tools/call` | Yes | Yes | `Near parity` | Core RPC path is implemented in both. |
| One-shot CLI tool execution | `codebase-memory-mcp cli ...` | `cbm cli ...` | `Near parity` | Both support direct command-line tool invocation. |
| CLI progress output | Rich progress sink with per-stage pipeline events | Minimal `tool_start` / `tool_done` events for `cli --progress` | `Partial` | Zig progress is useful but much thinner than the original phase-aware sink. |
| Idle-store / session-lifecycle extras | Present in the original MCP runtime | Not implemented in the Zig runtime | `Partial` | The Zig runtime focuses on the persistent store + watcher path, not full lifecycle parity. |
| Signal-driven graceful shutdown | Yes | Not explicitly implemented | `Partial` | The C runtime sets signal handlers; the Zig runtime relies on normal process teardown. |

### 2.2 MCP Tools

| Tool | Original C | Zig Port | Status | Notes |
|------|------------|----------|--------|-------|
| `index_repository` | Full | Implemented | `Near parity` | Core readiness tool; interop-gated. |
| `search_graph` | Full | Implemented with rich filters and pagination | `Near parity` | The Zig Phase 5 work specifically broadened this toward daily-use parity. |
| `query_graph` | Full Cypher-oriented surface | Read-only Cypher-like subset | `Partial` | Broad enough for current daily-use workflows, not full parity. |
| `trace_call_path` / `trace_path` | Calls, data-flow, cross-service, risk labels, include-tests | Call-edge traversal only | `Partial` | Zig does not implement the broader tracing modes or risk labeling. |
| `get_code_snippet` | Full | Implemented | `Near parity` | Zig supports exact lookup, suffix fallback, ambiguity suggestions, neighbor info. |
| `get_graph_schema` | Full | Implemented | `Near parity` | Good match for the low-risk public surface. |
| `get_architecture` | Languages, packages, entry points, routes, hotspots, boundaries, layers, clusters, ADR | Structure, dependencies, hotspots, entry points, routes summary | `Partial` | Zig ships a practical summary, not the original’s full architecture analysis stack. |
| `search_code` | Graph-augmented grep with ranking/dedup | Implemented for compact/full/files modes | `Partial` | Useful and shipped, but not documented as full ranking/dedup parity with the C implementation. |
| `list_projects` | Full | Implemented | `Near parity` | Core readiness tool; counts remain diagnostic in first-gate comparisons. |
| `delete_project` | Full | Implemented | `Near parity` | Includes watcher unregistration in Zig. |
| `index_status` | Full | Implemented | `Near parity` | Exposed during Phase 3. |
| `detect_changes` | Git diff + impact + blast radius + risk classification | Git diff + impacted symbols + blast radius | `Partial` | Zig covers the main workflow but not the original’s fuller risk/reporting shape. |
| `manage_adr` | Implemented | Not implemented | `Deferred` | Explicitly kept outside the completed Zig target contract. |
| `ingest_traces` | Stubbed in original | Not implemented | `N/A` | Not a meaningful parity gap because the original feature is also not real. |

### 2.3 Important Tool-Contract Differences

| Difference | Original C | Zig Port | Why it matters |
|-----------|------------|----------|----------------|
| Indexing argument name | `repo_path` | `project_path` | Wrappers or fixtures must normalize this difference. |
| Trace tool naming | `trace_path` plus `trace_call_path` alias | `trace_call_path` only | The Zig port follows the clearer explicit name. |
| Trace entry argument | `function_name` | `start_node_qn` | Zig prefers deterministic graph identity over name-only lookup. |
| Trace modes | `calls`, `data_flow`, `cross_service` | call-edge traversal only | Users should not expect original trace modes in the Zig port. |
| Tools advertised via `tools/list` | 14 | 12 | Zig does not currently expose `manage_adr` or `ingest_traces`. |

## 3. Indexing Pipeline and Graph Construction

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| Structure pass | Yes | Yes | `Near parity` | Both build project/folder/file/module structure. |
| Definitions extraction | Broad AST extraction | Parser-backed for target languages plus fallback heuristics | `Partial` | Strong for the target slice, not full original breadth. |
| Import resolution | Yes | Yes | `Near parity` | Zig improved alias preservation and namespace-aware resolution in Phase 4. |
| Call resolution | Registry + import-aware resolution + some LSP hybrid paths | Registry + import-aware resolution | `Partial` | Zig does not implement the original LSP-assisted resolution path. |
| Usage / type-reference edges | Yes | Yes for current target slice | `Partial` | Zig ships usable `USAGE` extraction, but deeper local-dataflow and broader parity are deferred. |
| Semantic edges | Inherits / decorates / implements and related enrichment | Implemented for current target languages | `Partial` | Zig covers the daily-use slice, not the full original breadth. |
| Qualified-name helpers | Yes | Yes | `Near parity` | Explicit Phase 2 substrate work. |
| Registry / symbol lookup | Yes | Yes | `Near parity` | Explicit Phase 2 and Phase 4 work in Zig. |
| Incremental indexing | Yes | Yes | `Near parity` | Zig persists file hashes and reindexes changed slices. |
| Parallel extraction | Yes | Yes | `Near parity` | Zig has per-file local buffers plus merge/remap logic. |
| Similarity / near-clone detection | Yes (`SIMILAR_TO`) | Yes (`SIMILAR_TO`) | `Near parity` | Zig ships MinHash/LSH-based similarity edges in the current contract. |
| Transactional indexing guardrails | Yes | Yes | `Near parity` | Zig wraps pipeline writes in transactions and uses an index guard. |
| LSP hybrid type resolution | Present for Go/C/C++ in original | Not implemented | `Deferred` | The original README explicitly calls out LSP-style hybrid type resolution; Zig does not ship that layer. |
| Test tagging pass | Yes | Not implemented | `Deferred` | Original has `pass_tests.c`; Zig explicitly defers test tagging. |
| Git history coupling | Yes | Not implemented | `Deferred` | Original has `pass_githistory.c`; Zig explicitly defers it. |
| Config linking / config normalization | Yes | Not implemented | `Deferred` | Original has `pass_configures.c` and `pass_configlink.c`. |
| Route-node creation / cross-service graph | Yes | Not implemented | `Deferred` | Original has `pass_route_nodes.c`; Zig does not currently generate that graph layer. |
| Infra scanning (`Docker`, `K8s`, Terraform, etc.) | Yes in the original codebase | Not ported | `Cut` | Zig intentionally excludes the infra-scan family from the current port target. |
| OTLP traces | Stubbed | Not ported | `N/A` | Not a meaningful implemented-vs-implemented gap. |

## 4. Graph Model Coverage

This section compares what kinds of graph entities the two systems are built to produce.

| Graph entity / edge family | Original C | Zig Port | Status | Notes |
|----------------------------|------------|----------|--------|-------|
| Core code graph (`Project`, `Folder`, `File`, `Module`, `Class`, `Function`, `Method`, `Interface`, `Enum`) | Yes | Yes | `Near parity` | These are the backbone of the shipped Zig graph. |
| Core code edges (`CONTAINS_*`, `DEFINES`, `DEFINES_METHOD`, `CALLS`, `USAGE`) | Yes | Yes | `Near parity` | All are part of the current Zig daily-use contract. |
| `SIMILAR_TO` | Yes | Yes | `Near parity` | Landed in Zig Phase 6. |
| `CONFIGURES` / `WRITES` style edges | Yes | Present in the Zig graph | `Partial` | Observed in the Zig project graph, but broader config-link parity remains deferred. |
| Route graph (`Route`, `HTTP_CALLS`, `ASYNC_CALLS`, `HANDLES`, route-linked data flows) | Yes | Not shipped | `Deferred` | This is one of the clearest remaining graph-model differences. |
| Resource / infra graph (`Resource`, K8s/Kustomize entities) | Yes | Not shipped | `Cut` | Intentionally outside the Zig scope. |
| `TESTS` / test metadata | Yes | Not shipped | `Deferred` | Test tagging remains future work. |
| `FILE_CHANGES_WITH` | Yes | Not shipped | `Deferred` | Depends on the deferred git-history pass. |
| `USES_TYPE` and richer edge families | Yes | Partially approximated through `USAGE` | `Partial` | Zig has useful usage edges but not the full long-tail edge vocabulary. |

## 5. Language Support

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| Extension / filename detection | Broad, documented as 66 languages | Broad language enum and extension mapping in `src/discover.zig` | `Near parity` | Zig detects far more languages than it currently parses deeply. |
| Tree-sitter-backed definitions across the full language set | Yes | No | `Partial` | This is one of the major deliberate scope reductions in the Zig port. |
| Tree-sitter-backed definitions for Python | Yes | Yes | `Near parity` | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for JavaScript | Yes | Yes | `Near parity` | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for TypeScript / TSX | Yes | Yes | `Near parity` | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Rust | Yes | Yes | `Near parity` | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Zig | Not a headline original language, but supported in the port target | Yes | `Near parity` | Zig is a first-class target language in the port. |
| Fallback heuristics for non-target languages | Broad AST extraction in original | Heuristic symbol extraction fallback in Zig | `Partial` | Zig intentionally keeps heuristics for unsupported deep-parser languages. |
| Hybrid type/LSP resolution for Go, C, C++ | Yes | No | `Deferred` | Explicit original differentiator not currently ported. |

## 6. Runtime and Operations

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| Default stdio MCP server | Yes | Yes | `Near parity` | This is the default mode in both entrypoints. |
| Persistent runtime cache / DB | Yes | Yes | `Near parity` | Zig uses `CBM_CACHE_DIR` or `~/.cache/codebase-memory-zig`. |
| Watcher-driven auto-reindex | Yes | Yes | `Near parity` | Both use git-based watcher logic. |
| Startup auto-index | Yes | Yes | `Near parity` | Zig supports config-driven or env-driven startup auto-index. |
| Previously indexed project watcher registration | Yes | Yes | `Near parity` | Explicitly wired in Zig Phase 6. |
| UI runtime flags (`--ui`, `--port`) | Yes | No | `Cut` | Zig does not ship the UI server. |
| Startup update notification | Yes | No | `Deferred` | The original README documents update checks on startup. |
| Benchmarking / soak / security scripts | Present | Not present | `Partial` | Zig currently has only the interop harness plus local scratch scripts. |

## 7. CLI and Productization

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| `install` | Yes | Yes | `Partial` | Zig installs only Codex CLI and Claude Code MCP config entries. |
| `uninstall` | Yes | Yes | `Partial` | Same scope difference as `install`. |
| `update` | Yes, release-oriented updater | Yes, config-refresh for current binary path | `Partial` | Zig explicitly defers binary self-replacement for source builds. |
| `config` | Yes | Yes | `Near parity` | Zig supports persisted config including `auto_index`, `auto_index_limit`, and `download_url`. |
| `cli --progress` | Yes, rich progress sink | Yes, minimal lifecycle events | `Partial` | Useful but narrower than the original. |
| Auto-detected agent integrations | 10 agents | 2 agents | `Partial` | Zig currently supports Codex CLI and Claude Code only. |
| Agent instructions / skills / hooks installation | Yes | No | `Deferred` | Original installer configures instruction files, skills, and reminders/hooks. |
| Manual agent config support | Yes | Yes for the two shipped agent targets | `Near parity` | Zig writes the correct config files for Codex CLI and Claude Code. |

## 8. Build, Packaging, and Repository Shape

| Capability | Original C | Zig Port | Status | Notes |
|-----------|------------|----------|--------|-------|
| Primary build system | Make + shell scripts | `zig build` | `Partial` | Both are buildable, but the Zig repo has not yet reproduced the original’s packaging/release scaffolding. |
| Setup scripts | Yes (`scripts/setup.sh`, `setup-windows.ps1`) | No equivalent setup scripts in this repo | `Partial` | The Zig repo’s install path is through the binary’s own CLI commands. |
| UI asset embedding | Yes | No | `Cut` | Tied to the UI subsystem. |
| Security / audit / benchmark script set | Broad script suite | Not present | `Deferred` | Not part of the completed Zig target contract. |
| Interop harness against the original | Not applicable | Yes | `Near parity` | This is a Zig-side advantage for tracking compatibility over time. |

## 9. What the Zig Port Can Truthfully Claim Today

| Claim | Assessment |
|------|------------|
| It is a useful daily-use MCP server for structural code intelligence | Yes |
| It matches the original on the documented readiness gate | Yes |
| It implements the completed post-readiness target contract described in this repo | Yes |
| It is a full feature-for-feature port of the original C project | No |
| It has no meaningful remaining work in its chosen daily-use target | Yes |
| It still has optional future parity work if exhaustive comparison is the goal | Yes |

## 10. Biggest Remaining Differences

If someone asks “what still separates the Zig port from the original?”, the shortest accurate answer is:

| Difference | Why it matters |
|-----------|----------------|
| No `manage_adr` | The original has ADR persistence and guided architecture documentation flows. |
| No full Cypher parity | Some advanced graph query patterns remain C-only. |
| No route / cross-service graph stack | The original can model HTTP and async route relationships more richly. |
| No LSP-assisted hybrid resolution | Some higher-fidelity call/type resolution paths remain original-only. |
| No test-tagging, git-history, or config-link passes | The original still has more metadata and impact-analysis depth. |
| No UI subsystem | The original can run a graph visualization UI; the Zig port intentionally cannot. |
| Much narrower installer ecosystem | The original configures 10 agents plus hooks/instructions; Zig currently configures 2 agents and only MCP entries. |

## Bottom Line

The Zig port is best understood as:

- complete for its documented interoperability gate
- complete for its documented daily-use target contract
- not yet a full feature-for-feature replacement for every subsystem in the original C project

That means the Zig port is already strong where this repo has chosen to compete:

- core indexing
- practical MCP querying
- watcher/incremental/parallel/runtime behavior
- source-build-friendly CLI/productization for Codex CLI and Claude Code

The remaining gap is no longer “the basics do not work.” The remaining gap is the long tail:

- richer query parity
- richer graph-model parity
- broader installer/product surface
- optional subsystems that this repo has explicitly deferred or cut
