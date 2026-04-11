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

`Interoperable?` is stricter than simple feature existence. Mark `Yes` only where this document is willing to make a full-parity claim for that row. Shared implementation alone is not enough.

## Executive Summary

| Area | Original C | Zig Port | Status | Interoperable? |
|------|------------|----------|--------|----------------|
| Readiness/interoperability gate | Full shared-capability reference implementation | Expanded shared-capability parity harness completed, automated, and passing | `Near parity` | Yes |
| Daily-use MCP surface | Full 14-tool surface, though `ingest_traces` is stubbed | Complete current-target daily-use surface, but without `manage_adr` and `ingest_traces` | `Partial` | No |
| Core indexing pipeline | Broad multi-pass pipeline including routes, tests, config links, infra scans, git history, similarity | Strong core pipeline for structure, definitions, imports, calls, usages, semantics, incremental, parallel, similarity | `Partial` | No |
| Runtime lifecycle | Watcher, auto-index, update notifications, UI-capable runtime | Watcher, auto-index, incremental, transactional indexing, persistent runtime DB | `Near parity` | Yes |
| CLI/productization | Rich install/update/config for 10 agents plus hooks/instructions | Source-build-friendly install/update/config for Codex CLI and Claude Code | `Partial` | No |
| Optional/long-tail systems | UI, route graph, ADR, infra/resource indexing, git history, tests, config linking | Explicitly deferred or cut | `Deferred` / `Cut` | No |

## 1. Project Scope and Product Shape

| Capability | Original C (`codebase-memory-mcp`) | Zig Port (`codebase-memory-zig`) | Status | Interoperable? | Notes |
|-----------|-------------------------------------|----------------------------------|--------|----------------|-------|
| Stated product goal | Full-featured code intelligence engine with 14 MCP tools, UI variant, 66 languages, 10-agent install path | Interoperable, higher-performance and more reliable daily-use port of the original | `Partial` | No | The Zig repo explicitly treats completion of Phase 7 as completion of the current target contract, not exhaustive parity. |
| Readiness gate | Reference side of the interop harness | Completed and passing: `Strict matches: 58`, `Diagnostic-only comparisons: 9`, `Mismatches: 0` | `Near parity` | Yes | The expanded shared-capability harness is now fully green and is the strongest current parity claim in the Zig repo. |
| Broader post-readiness target | Everything in the original project | Current target contract only; long-tail parity moved to deferred backlog | `Partial` | No | See `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`. |
| Built-in graph UI | Yes, optional UI binary / HTTP server | No | `Cut` | No | Original has `src/ui/*` and `--ui` flags. Zig intentionally does not port the UI. |
| Release/install packaging | Prebuilt release artifacts plus setup scripts and install scripts | Source-build oriented repo with `zig build`; no release/install script set in the Zig repo | `Partial` | No | The Zig repo has a working CLI installer layer but not the original’s packaging/distribution surface. |

## 2. MCP Protocol and Tool Surface

### 2.1 Protocol Layer

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| `initialize` | Yes | Yes | `Near parity` | Yes | Both serve stdio JSON-RPC MCP. |
| `tools/list` | Yes, advertises 14 tools | Yes, advertises the 12 overlapping implemented tools | `Near parity` | Yes | Shared tool-schema parity is now green; the remaining count difference is `manage_adr` plus the original's stub `ingest_traces`. |
| `tools/call` | Yes | Yes | `Near parity` | Yes | Core RPC path is implemented in both. |
| One-shot CLI tool execution | `codebase-memory-mcp cli ...` | `cbm cli ...` | `Near parity` | Yes | Both support direct command-line tool invocation. |
| CLI progress output | Rich progress sink with per-stage pipeline events | Shared phase-aware progress stream for overlapping commands | `Near parity` | Yes | The temp-HOME CLI parity check in the interop harness now reports `cli_progress: match`; richer original-only lifecycle/runtime extras remain separate rows. |
| Idle-store / session-lifecycle extras | Present in the original MCP runtime | Not implemented in the Zig runtime | `Partial` | No | The Zig runtime focuses on the persistent store + watcher path, not full lifecycle parity. |
| Signal-driven graceful shutdown | Yes | Not explicitly implemented | `Partial` | No | The C runtime sets signal handlers; the Zig runtime relies on normal process teardown. |

### 2.2 MCP Tools

| Tool | Original C | Zig Port | Status | Interoperable? | Notes |
|------|------------|----------|--------|----------------|-------|
| `index_repository` | Full | Implemented | `Near parity` | Yes | Core readiness tool; interop-gated. |
| `search_graph` | Full | Implemented with rich filters and pagination | `Near parity` | Yes | The Zig Phase 5 work specifically broadened this toward daily-use parity. |
| `query_graph` | Full Cypher-oriented surface | Shared read-only Cypher parity floor for the fixture and harness query set | `Near parity` | Yes | The Zig executor now matches the original on the overlapping read-only query forms this repo counts as shared capability, including row ordering for the parity fixtures. |
| `trace_call_path` / `trace_path` | Calls, data-flow, cross-service, risk labels, include-tests | Call-edge traversal only | `Partial` | No | Zig does not implement the broader tracing modes or risk labeling. |
| `get_code_snippet` | Full | Implemented | `Near parity` | Yes | Zig supports exact lookup, suffix fallback, ambiguity suggestions, neighbor info. |
| `get_graph_schema` | Full | Implemented | `Near parity` | Yes | Good match for the low-risk public surface. |
| `get_architecture` | Languages, packages, entry points, routes, hotspots, boundaries, layers, clusters, ADR | Shared architecture summary sections, counts, and structured fields aligned on the parity fixtures | `Near parity` | Yes | The harness now proves the overlapping architecture-summary contract is aligned; richer original-only sections such as ADR management remain outside this shared row. |
| `search_code` | Graph-augmented grep with ranking/dedup | Shared compact/full/files behavior aligned on grouping, labels, and ranking for the parity fixtures | `Near parity` | Yes | The Zig search path now matches the original on the overlapping result-shaping contract exercised by the fixture corpus, including the JavaScript `boot` label case. |
| `list_projects` | Full | Implemented | `Near parity` | Yes | Core readiness tool; counts remain diagnostic in first-gate comparisons. |
| `delete_project` | Full | Implemented | `Near parity` | Yes | Includes watcher unregistration in Zig. |
| `index_status` | Full | Implemented | `Near parity` | Yes | Exposed during Phase 3. |
| `detect_changes` | Git diff + impact + blast radius + risk classification | Shared git-diff, impacted-symbol, blast-radius, and reporting contract aligned for the parity fixtures | `Near parity` | Yes | Zig now matches the original's overlapping `scope` mode behavior and shared reporting shape on the verified fixture scenarios. |
| `manage_adr` | Implemented | Not implemented | `Deferred` | No | Explicitly kept outside the completed Zig target contract. |
| `ingest_traces` | Stubbed in original | Not implemented | `N/A` | No | Not a meaningful parity gap because the original feature is also not real. |

### 2.3 Important Tool-Contract Differences

| Difference | Original C | Zig Port | Why it matters |
|-----------|------------|----------|----------------|
| Indexing argument name | `repo_path` | `project_path` | Wrappers or fixtures must normalize this difference. |
| Trace tool naming | `trace_path` plus `trace_call_path` alias | `trace_call_path` only | The Zig port follows the clearer explicit name. |
| Trace entry argument | `function_name` | `start_node_qn` | Zig prefers deterministic graph identity over name-only lookup. |
| Trace modes | `calls`, `data_flow`, `cross_service` | call-edge traversal only | Users should not expect original trace modes in the Zig port. |
| Tools advertised via `tools/list` | 14 total | 12 overlapping implemented tools | Shared overlap is aligned; the remaining count difference is deferred `manage_adr` plus the original's stub `ingest_traces`. |

## 3. Indexing Pipeline and Graph Construction

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Structure pass | Yes | Yes | `Near parity` | Yes | Both build project/folder/file/module structure. |
| Definitions extraction | Broad AST extraction | Parser-backed for target languages plus fallback heuristics | `Partial` | No | Strong for the target slice, not full original breadth. |
| Import resolution | Yes | Yes | `Near parity` | Yes | Zig improved alias preservation and namespace-aware resolution in Phase 4. |
| Call resolution | Registry + import-aware resolution + some LSP hybrid paths | Registry + import-aware resolution | `Partial` | No | Zig does not implement the original LSP-assisted resolution path. |
| Usage / type-reference edges | Yes | Yes for current target slice | `Partial` | No | Zig ships usable `USAGE` extraction, but deeper local-dataflow and broader parity are deferred. |
| Semantic edges | Inherits / decorates / implements and related enrichment | Implemented for current target languages | `Partial` | No | Zig covers the daily-use slice, not the full original breadth. |
| Qualified-name helpers | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 substrate work. |
| Registry / symbol lookup | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 and Phase 4 work in Zig. |
| Incremental indexing | Yes | Yes | `Near parity` | Yes | Zig persists file hashes and reindexes changed slices. |
| Parallel extraction | Yes | Yes | `Near parity` | Yes | Zig has per-file local buffers plus merge/remap logic. |
| Similarity / near-clone detection | Yes (`SIMILAR_TO`) | Yes (`SIMILAR_TO`) | `Near parity` | Yes | Zig ships MinHash/LSH-based similarity edges in the current contract. |
| Transactional indexing guardrails | Yes | Yes | `Near parity` | Yes | Zig wraps pipeline writes in transactions and uses an index guard. |
| LSP hybrid type resolution | Present for Go/C/C++ in original | Not implemented | `Deferred` | No | The original README explicitly calls out LSP-style hybrid type resolution; Zig does not ship that layer. |
| Test tagging pass | Yes | Not implemented | `Deferred` | No | Original has `pass_tests.c`; Zig explicitly defers test tagging. |
| Git history coupling | Yes | Not implemented | `Deferred` | No | Original has `pass_githistory.c`; Zig explicitly defers it. |
| Config linking / config normalization | Yes | Not implemented | `Deferred` | No | Original has `pass_configures.c` and `pass_configlink.c`. |
| Route-node creation / cross-service graph | Yes | Not implemented | `Deferred` | No | Original has `pass_route_nodes.c`; Zig does not currently generate that graph layer. |
| Infra scanning (`Docker`, `K8s`, Terraform, etc.) | Yes in the original codebase | Not ported | `Cut` | No | Zig intentionally excludes the infra-scan family from the current port target. |
| OTLP traces | Stubbed | Not ported | `N/A` | No | Not a meaningful implemented-vs-implemented gap. |

## 4. Graph Model Coverage

This section compares what kinds of graph entities the two systems are built to produce.

| Graph entity / edge family | Original C | Zig Port | Status | Interoperable? | Notes |
|----------------------------|------------|----------|--------|----------------|-------|
| Core code graph (`Project`, `Folder`, `File`, `Module`, `Class`, `Function`, `Method`, `Interface`, `Enum`) | Yes | Yes | `Near parity` | Yes | These are the backbone of the shipped Zig graph. |
| Core code edges (`CONTAINS_*`, `DEFINES`, `DEFINES_METHOD`, `CALLS`, `USAGE`) | Yes | Yes | `Near parity` | Yes | All are part of the current Zig daily-use contract. |
| `SIMILAR_TO` | Yes | Yes | `Near parity` | Yes | Landed in Zig Phase 6. |
| `CONFIGURES` / `WRITES` style edges | Yes | Present in the Zig graph | `Partial` | No | Observed in the Zig project graph, but broader config-link parity remains deferred. |
| Route graph (`Route`, `HTTP_CALLS`, `ASYNC_CALLS`, `HANDLES`, route-linked data flows) | Yes | Not shipped | `Deferred` | No | This is one of the clearest remaining graph-model differences. |
| Resource / infra graph (`Resource`, K8s/Kustomize entities) | Yes | Not shipped | `Cut` | No | Intentionally outside the Zig scope. |
| `TESTS` / test metadata | Yes | Not shipped | `Deferred` | No | Test tagging remains future work. |
| `FILE_CHANGES_WITH` | Yes | Not shipped | `Deferred` | No | Depends on the deferred git-history pass. |
| `USES_TYPE` and richer edge families | Yes | Partially approximated through `USAGE` | `Partial` | No | Zig has useful usage edges but not the full long-tail edge vocabulary. |

## 5. Language Support

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Extension / filename detection | Broad, documented as 66 languages | Broad language enum and extension mapping in `src/discover.zig` | `Near parity` | Yes | Zig detects far more languages than it currently parses deeply. |
| Tree-sitter-backed definitions across the full language set | Yes | No | `Partial` | No | This is one of the major deliberate scope reductions in the Zig port. |
| Tree-sitter-backed definitions for Python | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for JavaScript | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for TypeScript / TSX | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Rust | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Zig | Not a headline original language, but supported in the port target | Yes | `Near parity` | No | Zig is a first-class target language in the port. |
| Fallback heuristics for non-target languages | Broad AST extraction in original | Heuristic symbol extraction fallback in Zig | `Partial` | No | Zig intentionally keeps heuristics for unsupported deep-parser languages. |
| Hybrid type/LSP resolution for Go, C, C++ | Yes | No | `Deferred` | No | Explicit original differentiator not currently ported. |

## 6. Runtime and Operations

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Default stdio MCP server | Yes | Yes | `Near parity` | Yes | This is the default mode in both entrypoints. |
| Persistent runtime cache / DB | Yes | Yes | `Near parity` | Yes | Zig uses `CBM_CACHE_DIR` or `~/.cache/codebase-memory-zig`. |
| Watcher-driven auto-reindex | Yes | Yes | `Near parity` | Yes | Both use git-based watcher logic. |
| Startup auto-index | Yes | Yes | `Near parity` | Yes | Zig supports config-driven or env-driven startup auto-index. |
| Previously indexed project watcher registration | Yes | Yes | `Near parity` | Yes | Explicitly wired in Zig Phase 6. |
| UI runtime flags (`--ui`, `--port`) | Yes | No | `Cut` | No | Zig does not ship the UI server. |
| Startup update notification | Yes | No | `Deferred` | No | The original README documents update checks on startup. |
| Benchmarking / soak / security scripts | Present | Not present | `Partial` | No | Zig currently has only the interop harness plus local scratch scripts. |

## 7. CLI and Productization

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| `install` | Yes | Yes | `Partial` | No | Zig installs only Codex CLI and Claude Code MCP config entries. |
| `uninstall` | Yes | Yes | `Partial` | No | Same scope difference as `install`. |
| `update` | Yes, release-oriented updater | Yes, config-refresh for current binary path | `Partial` | No | Zig explicitly defers binary self-replacement for source builds. |
| `config` | Yes | Yes | `Near parity` | Yes | Zig supports persisted config including `auto_index`, `auto_index_limit`, and `download_url`. |
| `cli --progress` | Yes, rich progress sink | Yes, shared phase-aware parity stream for overlapping commands | `Near parity` | Yes | Verified by the interop harness temp-HOME CLI check, which now reports `cli_progress: match`. |
| Auto-detected agent integrations | 10 agents | 2 agents | `Partial` | No | Zig currently supports Codex CLI and Claude Code only. |
| Agent instructions / skills / hooks installation | Yes | No | `Deferred` | No | Original installer configures instruction files, skills, and reminders/hooks. |
| Manual agent config support | Yes | Yes for the two shipped agent targets | `Near parity` | Yes | Zig writes the correct config files for Codex CLI and Claude Code. |

## 8. Build, Packaging, and Repository Shape

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Primary build system | Make + shell scripts | `zig build` | `Partial` | No | Both are buildable, but the Zig repo has not yet reproduced the original’s packaging/release scaffolding. |
| Setup scripts | Yes (`scripts/setup.sh`, `setup-windows.ps1`) | No equivalent setup scripts in this repo | `Partial` | No | The Zig repo’s install path is through the binary’s own CLI commands. |
| UI asset embedding | Yes | No | `Cut` | No | Tied to the UI subsystem. |
| Security / audit / benchmark script set | Broad script suite | Not present | `Deferred` | No | Not part of the completed Zig target contract. |
| Interop harness against the original | Not applicable | Yes | `Near parity` | No | This is a Zig-side advantage for tracking compatibility over time. |

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
