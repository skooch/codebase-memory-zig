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
  - `docs/interop-testing-review.md`
  - `docs/plans/implemented/interoperability-alignment-readiness-plan.md`
  - `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`
- Verification and CI wiring:
  - `.github/workflows/ci.yml`
  - `.github/workflows/interop-nightly.yml`
  - `.github/workflows/ops-checks.yml`
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
| Daily-use MCP surface | Full 14-tool surface, though `ingest_traces` is stubbed | Complete overlapping tool surface, now served through a stable MCP contract with internal hybrid routing for search/snippet/architecture/change detection | `Partial` | No |
| Core indexing pipeline | Broad multi-pass pipeline including routes, tests, config links, infra scans, git history, similarity | Strong core pipeline for structure, definitions, imports, calls, usages, semantics, incremental, parallel, similarity, plus embedded FTS5 refresh and optional SCIP sidecar import | `Partial` | No |
| Runtime lifecycle | Watcher, auto-index, update notifications, UI-capable runtime | Watcher, auto-index, incremental, transactional indexing, persistent runtime DB | `Near parity` | Yes |
| CLI/productization | Rich install/update/config for 10 agents plus hooks/instructions | Source-build-friendly install/update/config for the broader 10-agent matrix, with explicit shipped-vs-detected scope and fixture-backed extras coverage | `Partial` | No |
| Optional/long-tail systems | UI, route graph, infra/resource indexing, git history, config linking | Git history coupling implemented; graph-model parity fixture contract completed for route nodes and config linking; UI and infra scanning remain deferred or cut | `Partial` / `Cut` | No |

## Verification Posture

The repository now has broad automated coverage, but it does **not** have an exhaustive suite for every feature or edge case.

Broad automated coverage in the current repo:

- `zig build test` exercises unit and integration coverage across the core modules, including MCP framing and lifecycle, discovery, extraction, pipeline passes, query routing, graph buffer/store behavior, runtime lifecycle, route and event-topic synthesis, hybrid sidecars, git-history coupling, and installer or config logic.
- `.github/workflows/ci.yml` blocks merges on `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, `bash scripts/run_cli_parity.sh --zig-only`, formatting, and `zlint`.
- `.github/workflows/interop-nightly.yml` runs the full Zig-vs-C interop and CLI parity comparison against the reference implementation on a weekly schedule.
- `.github/workflows/ops-checks.yml` runs the Zig-only benchmark, soak, and static security audit suites on push and PR.

What this does **not** justify claiming:

- exhaustive tool-surface parity for every MCP edge case
- exhaustive framework-specific route or async-broker coverage
- exhaustive Windows-native runtime, installer, and archive behavior
- exhaustive packaging and setup regression coverage across all shells and platforms

The current automated posture is strong enough to support the repo's daily-use parity claims. It is not strong enough to claim that every implemented feature and every error path is exhaustively locked down.

Current audit note on `2026-04-19`:

- `zig build`: pass
- `zig build test`: pass
- `bash scripts/run_cli_parity.sh --zig-only`: pass
- `bash scripts/run_interop_alignment.sh --zig-only`: pass (`31/31`)
- `bash scripts/run_benchmark_suite.sh --zig-only --manifest testdata/bench/stress-manifest.json --report-dir .benchmark_reports/ops`: pass
- `bash scripts/run_soak_suite.sh --iterations 3 --report-dir .soak_reports/ci`: pass
- `bash scripts/run_security_audit.sh .security_reports/ci`: pass
- `bash scripts/run_interop_alignment.sh`: completed against the local C reference checkout with `0` mismatches in the broader parity surface
- `bash scripts/run_cli_parity.sh`: pass with no full-compare mismatches

## 1. Project Scope and Product Shape

| Capability | Original C (`codebase-memory-mcp`) | Zig Port (`codebase-memory-zig`) | Status | Interoperable? | Notes |
|-----------|-------------------------------------|----------------------------------|--------|----------------|-------|
| Stated product goal | Full-featured code intelligence engine with 14 MCP tools, UI variant, 66 languages, 10-agent install path | Interoperable, higher-performance and more reliable daily-use port of the original | `Partial` | No | The Zig repo explicitly treats completion of Phase 7 as completion of the current target contract, not exhaustive parity. |
| Readiness gate | Reference side of the interop harness | Completed and passing: `Strict matches: 58`, `Diagnostic-only comparisons: 9`, `Mismatches: 0` | `Near parity` | Yes | The first-gate harness is green; the expanded full harness now reports 31 fixtures, 237 comparisons, 135 strict matches, 36 diagnostic-only comparisons, 0 mismatches, and `cli_progress: match`. |
| Broader post-readiness target | Everything in the original project | Current target contract only; long-tail parity moved to deferred backlog | `Partial` | No | See `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`. |
| Built-in graph UI | Yes, optional UI binary / HTTP server | No | `Cut` | No | Original has `src/ui/*` and `--ui` flags. Zig intentionally does not port the UI. |
| Release/install packaging | Prebuilt release artifacts plus setup scripts and install scripts | Standard `cbm` release archives, checksums, install scripts, setup scripts, install docs, and a repo-owned release workflow | `Near parity` | Yes | The Zig repo now proves standard-binary packaging for macOS and Windows artifacts. UI variants plus signing/attestation remain intentionally narrower than the original pipeline. |

## 2. MCP Protocol and Tool Surface

### 2.1 Protocol Layer

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| `initialize` | Yes | Yes | `Near parity` | Yes | Both serve stdio JSON-RPC MCP. |
| `tools/list` | Yes, advertises 14 tools | Yes, advertises the 13 overlapping implemented tools | `Near parity` | Yes | Shared tool-schema parity is now green; the only remaining count difference is the original's stub `ingest_traces`. |
| `tools/call` | Yes | Yes | `Near parity` | Yes | Core RPC path is implemented in both. |
| One-shot CLI tool execution | `codebase-memory-mcp cli ...` | `cbm cli ...` | `Near parity` | Yes | Both support direct command-line tool invocation. |
| CLI progress output | Rich progress sink with per-stage pipeline events | Shared phase-aware progress stream for overlapping commands | `Near parity` | Yes | The temp-HOME CLI parity check in the interop harness now reports `cli_progress: match`; richer original-only lifecycle/runtime extras remain separate rows. |
| Idle-store / session-lifecycle extras | Present in the original MCP runtime | Timed idle eviction of the shared runtime DB plus reopen on the next stdio tool call | `Near parity` | Yes | Zig now proves the overlapping idle close/reopen behavior with `bash scripts/test_runtime_lifecycle_extras.sh`. The original's per-project cached-store topology remains an internal design difference rather than a public contract gap for this repo. |
| Signal-driven graceful shutdown | Yes | Yes | `Near parity` | Yes | Zig now installs `SIGINT` / `SIGTERM` handlers and the runtime harness verifies clean shutdown while stdio is active. |

### 2.2 MCP Tools

| Tool | Original C | Zig Port | Status | Interoperable? | Notes |
|------|------------|----------|--------|----------------|-------|
| `index_repository` | Full | Implemented | `Near parity` | Yes | Core readiness tool; interop-gated. |
| `search_graph` | Full | Implemented with rich filters and pagination | `Near parity` | Yes | The Zig Phase 5 work specifically broadened this toward daily-use parity. |
| `query_graph` | Full Cypher-oriented surface | Shared read-only Cypher parity floor for node and edge reads, filtering, counts, distinct selection, and bounded boolean conditions | `Near parity` | Yes | The compare harness now scores shared query-contract parity instead of incidental row-shape drift when both sides satisfy the fixture floor. The former `go-parity` hard mismatch is now reclassified as diagnostic-only because the shared contract no longer over-asserts that receiver-owned method row. |
| `trace_call_path` / `trace_path` | Calls, data-flow, cross-service, risk labels, include-tests | Calls, data-flow, cross-service modes; multi-edge-type BFS; risk labels; test-file filtering; function_name alias; structured callees/callers response | `Near parity` | Yes | Zig now implements trace modes, risk classification, test filtering, and the richer response format matching the C reference surface. |
| `get_code_snippet` | Full | Implemented | `Near parity` | Yes | Zig supports exact lookup, suffix fallback, ambiguity suggestions, neighbor info. The full-compare harness now normalizes the shared snippet contract instead of scoring implementation-specific qualified-name formatting. |
| `get_graph_schema` | Full | Implemented | `Near parity` | Yes | Good match for the low-risk public surface. |
| `get_architecture` | Languages, packages, entry points, routes, hotspots, boundaries, layers, clusters, ADR | Shared architecture summary sections, counts, and structured fields aligned on the parity fixtures | `Near parity` | Yes | The harness now proves the overlapping architecture-summary contract is aligned; richer original-only route and clustering sections remain outside this shared row. |
| `search_code` | Graph-augmented grep with ranking/dedup | Shared compact/full/files behavior mostly aligned, but the new discovery-scope fixture shows a real scope divergence on ignored/generated files | `Partial` | No | The Zig search path now matches the original on the earlier parity fixtures, including the JavaScript `boot` label case, but the discovery-scope fixture shows the current C reference still returning `generated/bundle.js` and `src/nested/ghost.js` where Zig now enforces indexed-scope exclusion. |
| `list_projects` | Full | Implemented | `Near parity` | Yes | Core readiness tool; counts remain diagnostic in first-gate comparisons. |
| `delete_project` | Full | Implemented | `Near parity` | Yes | Includes watcher unregistration in Zig. |
| `index_status` | Full | Implemented | `Near parity` | Yes | Exposed during Phase 3. |
| `detect_changes` | Git diff + impact + blast radius + risk classification | Shared git-diff, impacted-symbol, blast-radius, and reporting contract aligned for the parity fixtures | `Near parity` | Yes | Zig now matches the original's overlapping `scope` mode behavior and shared reporting shape on the verified fixture scenarios. |
| `manage_adr` | Implemented | Implemented with shared `get`, `update`, and `sections` parity | `Near parity` | Yes | The interop harness now verifies the overlapping ADR tool contract on a local parity fixture. |
| `ingest_traces` | Stubbed in original | Not implemented | `N/A` | No | Not a meaningful parity gap because the original feature is also not real. |

### 2.3 Important Tool-Contract Differences

| Difference | Original C | Zig Port | Why it matters |
|-----------|------------|----------|----------------|
| Indexing argument name | `repo_path` | `project_path` | Wrappers or fixtures must normalize this difference. |
| Trace tool naming | `trace_path` plus `trace_call_path` alias | `trace_call_path` only | The Zig port follows the clearer explicit name. |
| Trace entry argument | `function_name` | `start_node_qn` (with `function_name` alias) | Zig accepts both; prefers qualified name but falls back to name-based search. |
| Trace modes | `calls`, `data_flow`, `cross_service` | `calls`, `data_flow`, `cross_service` | Zig now implements all three trace modes with matching edge type presets. |
| Tools advertised via `tools/list` | 14 total | 13 overlapping implemented tools | Shared overlap is aligned; the remaining count difference is the original's stub `ingest_traces`. |

## 3. Indexing Pipeline and Graph Construction

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Structure pass | Yes | Yes | `Near parity` | Yes | Both build project/folder/file/module structure. |
| Shared target-language definitions extraction | Broad AST extraction across the original language set | Parser-backed extraction aligned with the verified shared Python, JavaScript, TypeScript, and Rust contract, plus verified Zig-side expansion tranches for Go, Java, PowerShell, and GDScript | `Near parity` | Yes | The parity fixtures now lock shared definition inventory, ownership, and label behavior for the overlapping target languages. The additional Zig-side PowerShell and GDScript tranche is fixture-verified for parser-backed definitions, but remains a local expansion claim rather than an interoperability claim. |
| Import resolution | Yes | Yes | `Near parity` | Yes | Zig improved alias preservation and namespace-aware resolution in Phase 4, and the `typescript-import-cases` accuracy fixture now keeps that shared contract under interop coverage. |
| Shared call-resolution cases | Registry + import-aware resolution + some LSP hybrid paths | Registry + import-aware resolution aligned on the verified alias-heavy shared cases | `Near parity` | Yes | The interop harness now protects the overlapping call-edge contract directly, including the new `typescript-import-cases` fixture. The original's broader LSP-assisted path remains a separate deferred row. |
| Shared usage and type-reference edges | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | Phase 3 now locks the overlapping declaration-time `USAGE` and shared type-reference behavior on the parity fixtures; deeper data-flow remains outside this row. |
| Shared semantic-edge contract | Inherits / decorates / implements and related enrichment | Implemented and aligned for the shared decorator-focused overlap | `Near parity` | Yes | The verified shared contract now matches the original on persisted decorator edges and on the exercised empty-result cases for unsupported inheritance/implements rows. |
| Qualified-name helpers | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 substrate work. |
| Registry / symbol lookup | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 and Phase 4 work in Zig. |
| Incremental indexing | Yes | Yes | `Near parity` | Yes | Zig persists file hashes and reindexes changed slices. |
| Parallel extraction | Yes | Yes | `Near parity` | Yes | Zig has per-file local buffers plus merge/remap logic. |
| Similarity / near-clone detection | Yes (`SIMILAR_TO`) | Yes (`SIMILAR_TO`) | `Near parity` | Yes | Zig ships MinHash/LSH-based similarity edges in the current contract. |
| Transactional indexing guardrails | Yes | Yes | `Near parity` | Yes | Zig wraps pipeline writes in transactions and uses an index guard. |
| LSP hybrid type resolution | Present for Go/C/C++ in original | Optional repository sidecar for explicit Go call targets, preferred ahead of heuristic registry matches | `Partial` | No | Zig now accepts `.codebase-memory/hybrid-resolution.json` and proves the bounded Go-backed sidecar contract on a reproducible fixture. C/C++ support, compile-commands ingestion, and live LSP client integration remain deferred. |
| Test tagging pass | Yes | Yes for the verified shared Python fixture slice | `Near parity` | Yes | Zig now derives `TESTS` and `TESTS_FILE` from shared filename and call-edge rules on the parity fixture without reopening broader language-specific enrichment work. |
| Git history coupling | Yes | Implemented | `Near parity` | Yes | Zig pass uses subprocess `git log` (no libgit2); creates `FILE_CHANGES_WITH` edges with `co_changes` and `coupling_score` properties. |
| Config linking / config normalization | Yes | Implemented for the graph-model parity fixture contract plus env-style and YAML key-shape follow-on fixtures | `Near parity` | Yes | Zig implements Strategy 1 (key-symbol) and Strategy 2 (dependency-import matching); the strict shared fixtures now lock raw-key query visibility, `maxConnections -> max-connections`, dependency-import deduplication, env-style config keys such as `DATABASE_URL -> load_database_url`, and YAML key-shape cases covering both `api-base-url` and `apiBaseUrl`. |
| Route-node creation / cross-service graph | Yes | Implemented for the graph-model parity fixture contract | `Near parity` | Yes | Zig classifies call edges as `HTTP_CALLS`/`ASYNC_CALLS`, creates stub and concrete URL/path/topic `Route` nodes, emits verified decorator-backed `HANDLES`, has strict shared route-linked `DATA_FLOWS` plus async topic fixtures, and covers route summary exposure. The narrower `python-framework-cases` accuracy fixture now also keeps the shared decorator-backed `HANDLES` contract under interop coverage. Broader framework expansion remains optional future work. |
| Infra scanning (`Docker`, `K8s`, Terraform, etc.) | Yes in the original codebase | Not ported | `Cut` | No | Zig intentionally excludes the infra-scan family from the current port target. |
| OTLP traces | Stubbed | Not ported | `N/A` | No | Not a meaningful implemented-vs-implemented gap. |

## 4. Graph Model Coverage

This section compares what kinds of graph entities the two systems are built to produce.

| Graph entity / edge family | Original C | Zig Port | Status | Interoperable? | Notes |
|----------------------------|------------|----------|--------|----------------|-------|
| Core code graph (`Project`, `Folder`, `File`, `Module`, `Class`, `Function`, `Method`, `Interface`, `Enum`) | Yes | Yes | `Near parity` | Yes | These are the backbone of the shipped Zig graph. |
| Core code edges (`CONTAINS_*`, `DEFINES`, `DEFINES_METHOD`, `CALLS`, `USAGE`) | Yes | Yes | `Near parity` | Yes | All are part of the current Zig daily-use contract. |
| `SIMILAR_TO` | Yes | Yes | `Near parity` | Yes | Landed in Zig Phase 6. |
| Shared `CONFIGURES` contract | Yes | Yes for the verified shared fixture slices | `Near parity` | Yes | The parity fixtures now compare overlapping `CONFIGURES` rows directly, including the graph-model key-symbol normalization case; broader config-link systems remain deferred elsewhere. |
| Internal serving architecture | Graph-centric serving path | Hybrid internal serving path: SQLite graph core, FTS5 lexical index, optional SCIP sidecar overlay, and query router | `Near parity` | Yes | This is an internal implementation improvement in the Zig port; it deliberately preserves the interoperable MCP surface rather than creating a new client contract. |
| Route and event graph (`Route`, `EventTopic`, `HTTP_CALLS`, `ASYNC_CALLS`, `HANDLES`, `EMITS`, `SUBSCRIBES`, route-linked data flows) | Yes | Partial | `Partial` | No | Zig now creates concrete URL/path/topic `Route` nodes, verified decorator-backed `HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared async topic caller rows, fixture-backed `EventTopic` nodes, and derived `EMITS` / `SUBSCRIBES` edges with architecture and cross-service trace visibility. The broader route slice now also has zig-only verified keyword-registration, generic `requests.request`, and `celery.send_task` fixtures, but those remain diagnostic-only in the full compare because the current C reference still returns empty row sets there. Higher-order analytics and broader framework coverage still remain open. |
| Resource / infra graph (`Resource`, K8s/Kustomize entities) | Yes | Not shipped | `Cut` | No | Intentionally outside the Zig scope. |
| `TESTS` / test metadata | Yes | Yes for the verified shared Python fixture slice | `Near parity` | Yes | The parity fixture now locks shared `TESTS` and `TESTS_FILE` rows plus file-level `is_test` metadata for the exercised Python naming rules. |
| `FILE_CHANGES_WITH` | Yes | Yes | `Near parity` | Yes | Zig git-history pass creates `FILE_CHANGES_WITH` edges with `co_changes` and `coupling_score` properties via subprocess `git log`. |
| Shared `USES_TYPE` contract | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | Phase 3 now compares the overlapping `USES_TYPE` queries directly for the exercised Python, TypeScript, and Rust cases instead of treating them as implicit approximations. |
| `THROWS` / `RAISES` | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | Zig extracts THROWS/RAISES edges from throw statements (JS/TS/TSX). Verified end-to-end on the edge-parity fixture. |
| Remaining long-tail edge families | Yes (broader vocabulary) | Limited to verified slices | `Partial` | No | The remaining or unproven original-overlap edges are `OVERRIDE` (Go-only) and broader positive `WRITES` / `READS` semantics. The public harness now proves a bounded shared zero-row `WRITES` / `READS` contract on the local-state micro-case, while `HANDLES` and route-linked `DATA_FLOWS` already have verified shared route slices. `CONTAINS_PACKAGE` was never implemented in C. |

## 5. Language Support

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Extension / filename detection | Broad, documented as 66 languages | Broad language enum and extension mapping in `src/discover.zig`, plus explicit env-only `CBM_EXTENSION_MAP` overrides | `Near parity` | Yes | Zig detects far more languages than it currently parses deeply, and the operational-controls parity lane now proves `.foo=python` remapping end to end. |
| Tree-sitter-backed definitions across the full language set | Yes | Parser-backed for the verified Python, JavaScript, TypeScript, TSX, Rust, Zig, Go, and Java tranche, but not the full original language set | `Partial` | No | The Zig port now has a broader parser-backed tranche, but it still does not reproduce the original's full language breadth. |
| Tree-sitter-backed definitions for Python | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for JavaScript | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for TypeScript / TSX | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Rust | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Go | Yes | Yes | `Near parity` | No | Zig now extracts Go functions, methods, structs, and interfaces with fixture-backed `go-basic` / `go-parity` coverage and green zig-only goldens. The remaining Go method-ownership row difference is now diagnostic-only rather than a hard shared-contract mismatch, so this row still stops short of a strict shared-parity claim. |
| Tree-sitter-backed definitions for Java | Yes | Yes | `Near parity` | No | Zig now extracts Java classes, interfaces, constructors, and methods with the new `java-basic` fixture green in zig-only mode. The scoped C compare still shows query-result deltas on `java-basic`, so this row remains a verified Zig expansion rather than a strict shared-parity claim. |
| Tree-sitter-backed definitions for Zig | Not a headline original language, but supported in the port target | Yes | `Near parity` | No | Zig is a first-class target language in the port. |
| Fallback heuristics for non-target languages | Broad AST extraction in original | Heuristic symbol extraction fallback in Zig | `Partial` | No | Zig intentionally keeps heuristics for unsupported deep-parser languages. |
| Hybrid type/LSP resolution for Go, C, C++ | Yes | No | `Deferred` | No | Explicit original differentiator not currently ported. |

## 6. Runtime and Operations

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Default stdio MCP server | Yes | Yes | `Near parity` | Yes | This is the default mode in both entrypoints, and Zig now has explicit `1 MiB` request-line and `4 MiB` response-envelope guardrails validated by unit tests plus the runtime harness. |
| Persistent runtime cache / DB | Yes | Yes | `Near parity` | Yes | Zig now proves cache-root selection through `CBM_CACHE_DIR`, Windows `LOCALAPPDATA`, Unix `XDG_CACHE_HOME`, and `HOME` fallback behavior via fixture-backed installer checks. |
| Watcher-driven auto-reindex | Yes | Yes | `Near parity` | Yes | Both use git-based watcher logic. |
| Startup auto-index | Yes | Yes | `Near parity` | Yes | Zig supports config-driven or env-driven startup auto-index. |
| Previously indexed project watcher registration | Yes | Yes | `Near parity` | Yes | Explicitly wired in Zig Phase 6. |
| UI runtime flags (`--ui`, `--port`) | Yes | No | `Cut` | No | Zig does not ship the UI server. |
| Startup update notification | Yes | Yes, one-shot notice on the first post-initialize response | `Near parity` | Yes | Zig now starts an update check on `initialize`, preserves the pending notice until it can be injected safely, and covers the env-override plus one-shot behavior in the runtime harness, including the `notifications/initialized` path staying silent before the first real tool response. |
| Benchmarking / soak / security scripts | Present | Repo-owned benchmark, soak, and static audit scripts plus CI wiring | `Near parity` | No | Zig now ships `scripts/run_benchmark_suite.sh`, `scripts/run_soak_suite.sh`, `scripts/run_security_audit.sh`, maintainer docs, and `.github/workflows/ops-checks.yml`. Verified on `2026-04-19`: Zig-only benchmark medians were `1340.308 ms` on `self-repo` and `72.769 ms` on `sqlite-amalgamation`, the soak suite reported `303.966 ms` p95 indexing over four iterations, and the static audit passed `17` checks with `0` failures. Remaining original-only layers are binary-string auditing, runtime network-trace auditing, fuzzing, and longer-duration soak coverage. |

## 7. CLI and Productization

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Shared `install` flow (`Codex CLI` / `Claude Code`) | Yes | Yes | `Near parity` | Yes | The temp-HOME CLI parity harness proves the overlapping install reporting and config-file effects for the two shared agent targets, and the Zig CLI now makes both the shipped scope and MCP-only side-effect behavior explicit. |
| Shared `uninstall` flow (`Codex CLI` / `Claude Code`) | Yes | Yes | `Near parity` | Yes | The same temp-HOME parity harness locks the overlapping uninstall behavior, including dry-run preservation and dual Claude config cleanup, while the Zig CLI now defaults uninstall scope to the shipped agent set and can skip extra side effects with `--mcp-only`. |
| Shared `update` flow (`Codex CLI` / `Claude Code`) | Yes, release-oriented updater plus config refresh | Yes, shared config refresh for the current binary path | `Near parity` | Yes | Phase 4 proves the overlapping config-refresh and reporting contract; original-only binary self-replacement remains a packaging difference rather than a shared-row failure, and the Zig CLI now keeps both scope and extras mode explicit. |
| `config` | Yes | Yes | `Near parity` | Yes | Zig now supports persisted config for `auto_index`, `auto_index_limit`, `idle_store_timeout_ms`, `update_check_disable`, `install_scope`, `install_extras`, and `download_url`, with temp-home fixture evidence for `set`, `get`, `list`, and `reset` on the operational controls it exposes today; env-only `CBM_EXTENSION_MAP` is verified separately through the same parity harness. |
| `cli --progress` | Yes, rich progress sink | Yes, shared phase-aware parity stream for overlapping commands | `Near parity` | Yes | Verified by the interop harness temp-HOME CLI check, which now reports `cli_progress: match`. |
| Auto-detected shared agent integrations | 10 agents total, including Codex CLI and Claude Code | 10 detected-scope agent targets now covered in the temp-home installer matrix | `Near parity` | Yes | The expanded temp-home harness now proves the broader detected-scope matrix and CLI reporting for Codex CLI, Claude Code, Gemini, Zed, OpenCode, Antigravity, Aider, KiloCode, VS Code, and OpenClaw, while the shipped default scope stays intentionally narrower. |
| Agent instructions / skills / hooks installation | Yes | Yes, with one consolidated Claude skill package instead of the original multi-skill layout | `Partial` | No | Zig now installs the broader instruction, hook, reminder, and rules side effects in the detected-scope matrix. The remaining material delta is the consolidated Claude skill packaging rather than the original four-skill layout. |
| Manual agent config support | Yes | Yes for the broader 10-agent detected-scope matrix | `Near parity` | Yes | The expanded temp-home harness now proves config writes and removals across Codex CLI, Claude Code, Gemini, Zed, OpenCode, Antigravity, KiloCode, VS Code, and OpenClaw, with PATH-based Aider instruction handling covered separately in the same lane. |

## 8. Build, Packaging, and Repository Shape

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Primary build system | Make + shell scripts | `zig build` plus repo-owned packaging and release scripts | `Partial` | No | Both repos now ship build and release scaffolding. The remaining difference is that Zig intentionally packages only the standard binary surface, not the original UI-oriented release variants. |
| Setup scripts | Yes (`scripts/setup.sh`, `setup-windows.ps1`) | Yes (`install.sh`, `install.ps1`, `scripts/setup.sh`, `scripts/setup-windows.ps1`) | `Near parity` | Yes | Zig now verifies both shell and PowerShell entrypoints against local packaged archives, while keeping the scope on the standard binary rather than the original's broader UI release set. |
| UI asset embedding | Yes | No | `Cut` | No | Tied to the UI subsystem. |
| Security / audit / benchmark script set | Broad script suite | Bounded repo-owned benchmark, soak, and static audit suite | `Near parity` | No | Zig now provides reproducible local and CI entrypoints for benchmark, soak, and static audit coverage. It still intentionally stops short of the original's binary-string, network-trace, fuzz, and multi-hour soak layers. |
| Interop harness against the original | Not applicable | Yes | `Near parity` | No | This is a Zig-side advantage for tracking compatibility over time. |

## 9. What the Zig Port Can Truthfully Claim Today

| Claim | Assessment |
|------|------------|
| It is a useful daily-use MCP server for structural code intelligence | Yes |
| It matches the original on the documented readiness gate | Yes |
| It implements the completed post-readiness target contract described in this repo | Yes |
| It is a full feature-for-feature port of the original C project | No |
| Its automated suite is exhaustive of all implemented features and edge cases | No |
| It has no meaningful remaining work in its chosen daily-use target | Yes |
| It still has optional future parity work if exhaustive comparison is the goal | Yes |

## 10. Biggest Remaining Differences

If someone asks “what still separates the Zig port from the original?”, the shortest accurate answer is:

| Difference | Why it matters |
|-----------|----------------|
| Discovery-scope semantics now diverge on the new fixture | Zig now enforces nested-ignore and generated-path exclusion in `search_code`, while the current C reference still returns those files on the discovery-scope fixture. |
| No exhaustive Cypher parity | The verified shared floor now covers node and edge reads, filters, counts, distinct selection, and bounded boolean conditions, but more advanced graph-query permutations remain unproven or C-only. |
| Broader route / cross-service framework expansion | Zig now emits verified decorator-backed `HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared async topic caller rows, route summaries, the shared `route-expansion-httpx` caller fixture, plus zig-only verified keyword route registrations, generic `requests.request("METHOD", "/path")`, and `celery.send_task("topic")`. The new framework fixtures are still diagnostic-only in the full compare because the current C reference returns empty row sets there, so broader shared-framework parity remains open. |
| No LSP-assisted hybrid resolution | Some higher-fidelity call/type resolution paths remain original-only. |
| Broader config normalization expansion | Git-history coupling is implemented, config linking has dependency-import matching and deduplication coverage, a strict shared key-symbol normalization fixture, a strict shared env-style config-key fixture, and a strict shared YAML key-shape fixture. Broader config-language and key-shape expansion remains optional future work, while `WRITES` / `READS` now have only a bounded shared zero-row harness contract rather than proven positive overlap. |
| No UI subsystem | The original can run a graph visualization UI; the Zig port intentionally cannot. |
| Installer ecosystem still differs | The Zig port now proves the broader 10-agent detected-scope matrix, hooks, reminders, and instructions, but it still keeps the shipped default scope narrower, defers binary self-replacement, and consolidates the Claude skill layout. |

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

- more exhaustive Cypher/query parity beyond the now-verified read-only floor
- higher-order graph analytics beyond the verified route, event-topic, and config fixture contract
- broader installer/product surface
- optional subsystems that this repo has explicitly deferred or cut

The testing story has the same shape: broad automated coverage for the chosen target contract, but not an exhaustive lock on every feature permutation, shell or OS path, or negative-path behavior.
