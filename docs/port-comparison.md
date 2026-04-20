# Port Comparison: `codebase-memory-zig` vs `codebase-memory-mcp`

## Purpose

This document is a source-backed comparison of the current Zig port against the original C implementation.

It is intentionally not a wish list. It describes:

- what the original C project ships today
- what the Zig port ships today
- where the Zig port is near-parity for the current target contract
- where the Zig port is intentionally narrower, deferred, or not ported

Baseline note:

- The original C side in this document is the latest released upstream baseline, `codebase-memory-mcp` `v0.6.0` from `2026-04-06`.
- The local checkout at `../codebase-memory-mcp` is older than that tag, so release-facing claims below are grounded in the tagged `v0.6.0` sources, not the stale local working tree.

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
- Original C release baseline (`DeusData/codebase-memory-mcp` `v0.6.0`):
  - release metadata from `gh release view v0.6.0 --repo DeusData/codebase-memory-mcp`
  - `README.md`
  - `src/main.c`
  - `src/mcp/mcp.c`
  - `src/pipeline/pipeline.h`
  - `src/pipeline/pass_definitions.c`
  - `src/pipeline/pass_semantic_edges.c`
  - `src/pipeline/pass_similarity.c`
  - `src/store/store.c`
  - `src/store/store.h`
  - `src/discover/discover.c`
  - `src/discover/discover.h`
  - `src/cli/cli.c`

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
| Daily-use MCP surface | Full 14-tool surface, with `v0.6.0` widening `search_graph` via BM25 `query` search and vector-backed `semantic_query`; `ingest_traces` remains stubbed | All 13 previously meaningful shared tools are implemented, but Zig does not ship the new `search_graph` discovery modes | `Partial` | No |
| Core indexing pipeline | Broad multi-pass pipeline including `full` / `moderate` / `fast` modes, `SIMILAR_TO`, `SEMANTICALLY_RELATED`, persisted `IMPORTS`, route/data-flow, channel edges, tests, config links, infra scans, and git history | Strong core pipeline for structure, definitions, calls, usages, incremental, parallel, similarity, route/event slices, plus embedded FTS5 refresh and optional SCIP sidecar import | `Partial` | No |
| Runtime lifecycle | Watcher, auto-index, update notifications, UI-capable runtime | Watcher, auto-index, incremental, transactional indexing, persistent runtime DB | `Near parity` | Yes |
| CLI/productization | Rich install/update/config for 10 agents plus hooks/instructions | Source-build-friendly install/update/config for the broader 10-agent matrix, with `112` exact zig-only CLI checks and a clean shared C compare on the overlapping Codex/Claude contract | `Partial` | No |
| Optional/long-tail systems | UI, semantic/vector search, route and channel graph expansion, infra/resource indexing, git history, config linking | Git history coupling implemented; graph-model parity fixture contract completed for route nodes and config linking; UI and infra scanning remain deferred or cut | `Partial` / `Cut` | No |

As of `2026-04-21`, the pre-`v0.6.0` shared contract is still largely closed. The newest latest-upstream gaps are concentrated in `search_graph` discovery modes (`query` / `semantic_query`), `moderate` indexing, `SEMANTICALLY_RELATED`, and the newer channel graph vocabulary (`Channel`, `EMITS`, `LISTENS_ON`). Older intentional scope choices such as the UI binary, infra/resource indexing, and deeper Cypher/LSP breadth still remain.

## Verification Posture

The repository now has broad automated coverage, but it does **not** have an exhaustive suite for every feature or edge case.

Broad automated coverage in the current repo:

- `zig build test` exercises unit and integration coverage across the core modules, including MCP framing and lifecycle, discovery, extraction, pipeline passes, query routing, graph buffer/store behavior, runtime lifecycle, route and event-topic synthesis, hybrid sidecars, git-history coupling, and installer or config logic.
- `.github/workflows/ci.yml` blocks merges on `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, `bash scripts/run_cli_parity.sh --zig-only`, formatting, and `zlint`.
- `.github/workflows/interop-nightly.yml` runs the full Zig-vs-C interop and CLI parity comparison against the reference implementation on pull requests and pushes to `main` when interop-relevant files change, while also retaining a weekly scheduled sweep and manual dispatch.
- `.github/workflows/ops-checks.yml` runs the Zig-only benchmark, soak, and static security audit suites on push and PR.

What this does **not** justify claiming:

- exhaustive tool-surface parity for every MCP edge case
- exhaustive framework-specific route or async-broker coverage
- exhaustive Windows-native runtime, installer, and archive behavior beyond the verified path-root and no-`HOME` fallback contract
- exhaustive packaging and setup regression coverage across all shells, hosts, and archive flows

The current automated posture is strong enough to support the repo's daily-use parity claims. It is not strong enough to claim that every implemented feature and every error path is exhaustively locked down.

Current audit note on `2026-04-21`:

- `zig build`: pass
- `zig build test`: pass
- `bash scripts/test_runtime_lifecycle.sh`: pass
- `bash scripts/test_runtime_lifecycle_extras.sh`: pass
- `bash scripts/run_cli_parity.sh --zig-only`: pass (`112` exact checks)
- `bash scripts/run_cli_parity.sh`: pass with `18` shared checks and `0` mismatches against the local C reference
- `bash scripts/run_interop_alignment.sh --zig-only`: pass (`39/39`)
- `bash scripts/run_benchmark_suite.sh --zig-only --manifest testdata/bench/stress-manifest.json --report-dir .benchmark_reports/ops`: pass
- `bash scripts/run_soak_suite.sh --iterations 3 --report-dir .soak_reports/ci`: pass
- `bash scripts/run_security_audit.sh .security_reports/ci`: pass
- `bash scripts/run_interop_alignment.sh`: completed against the local C reference checkout with `39` fixtures, `301` comparisons, `164` strict matches, `45` diagnostic-only comparisons, and `0` mismatches in the broader parity surface
- `bash scripts/run_cli_parity.sh`: pass with no full-compare mismatches

## 1. Project Scope and Product Shape

| Capability | Original C (`codebase-memory-mcp`) | Zig Port (`codebase-memory-zig`) | Status | Interoperable? | Notes |
|-----------|-------------------------------------|----------------------------------|--------|----------------|-------|
| Stated product goal | Full-featured code intelligence engine with 14 MCP tools, UI variant, 66 languages, 10-agent install path, plus `v0.6.0` semantic search and `moderate` indexing | Interoperable, higher-performance and more reliable daily-use port of the original | `Partial` | No | The Zig repo explicitly treats completion of Phase 7 as completion of the older target contract, not exhaustive parity with the latest upstream release. |
| Readiness gate | Reference side of the interop harness | Completed and passing: `Strict matches: 58`, `Diagnostic-only comparisons: 9`, `Mismatches: 0` | `Near parity` | Yes | The first-gate harness is green; the expanded full harness now reports 39 fixtures, 301 comparisons, 164 strict matches, 45 diagnostic-only comparisons, 0 mismatches, and `cli_progress: match`. |
| Broader post-readiness target | Everything in the original project | Current target contract only; long-tail parity moved to deferred backlog | `Partial` | No | See `docs/plans/implemented/post-readiness-zig-port-execution-plan.md`. |
| Built-in graph UI | Yes, optional UI binary / HTTP server | No | `Cut` | No | Original has `src/ui/*` and `--ui` flags. Zig intentionally does not port the UI. |
| Release/install packaging | Prebuilt release artifacts plus setup scripts and install scripts | Standard `cbm` release archives, checksums, a repo-owned release manifest, install scripts, setup scripts, install docs, and a validating release workflow | `Partial` | No | The Zig repo proves the standard-binary packaging path for macOS, Linux, and Windows artifacts, with merged-manifest validation in the release workflow. The latest-upstream release surface is still broader because Zig intentionally omits UI variants and does not ship the same signing, attestation, or provenance layers. |

## 2. MCP Protocol and Tool Surface

### 2.1 Protocol Layer

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| `initialize` | Yes | Yes | `Near parity` | Yes | The exact `protocol-contract` fixture now locks supported-version negotiation rather than only presence-checking the MCP handshake. |
| `tools/list` | Yes, advertises 14 tools | Yes, but the latest-upstream advertised schema still differs in visible ways | `Partial` | No | The exact `tool-surface-parity` fixture now locks tool inventory, `repo_path`, and the visible `ingest_traces` stub, but full parity is still blocked by the newer upstream `index_repository.mode` and `search_graph` discovery-mode contract. |
| `tools/call` | Yes | Yes | `Near parity` | Yes | The `protocol-contract` fixture now locks the exact shared `tools/call` protocol layer, including the accepted `ingest_traces` stub response. |
| One-shot CLI tool execution | `codebase-memory-mcp cli ...` | `cbm cli ...` | `Near parity` | Yes | The `protocol-contract` fixture now covers one-shot CLI tool execution at the exact contract layer rather than relying only on broader fixture assertions. |
| CLI progress output | Rich progress sink with per-stage pipeline events | Shared phase-aware progress stream for overlapping commands | `Near parity` | Yes | The temp-HOME CLI parity check in the interop harness now reports `cli_progress: match`; richer original-only lifecycle/runtime extras remain separate rows. |
| Idle-store / session-lifecycle extras | Present in the original MCP runtime | Timed idle eviction of the shared runtime DB plus reopen on the next stdio tool call | `Near parity` | Yes | Zig now proves the overlapping idle close/reopen behavior with `bash scripts/test_runtime_lifecycle_extras.sh`. The original's per-project cached-store topology remains an internal design difference rather than a public contract gap for this repo. |
| Signal-driven graceful shutdown | Yes | Yes | `Near parity` | Yes | Zig now installs `SIGINT` / `SIGTERM` handlers and the runtime harness verifies clean shutdown while stdio is active. |

### 2.2 MCP Tools

| Tool | Original C | Zig Port | Status | Interoperable? | Notes |
|------|------------|----------|--------|----------------|-------|
| `index_repository` | Full | Implemented, but without a real `moderate` mode | `Partial` | No | The exact `tool-surface-parity` fixture now proves `repo_path` compatibility and the public error contract for unsupported `moderate`, which keeps this row intentionally below full parity until the pipeline really supports that mode. |
| `search_graph` | Full, with `name_pattern`, BM25 `query`, and vector-backed `semantic_query` discovery modes | Implemented with rich structured filters and pagination, but without the upstream `query` / `semantic_query` paths | `Partial` | No | Zig matches much of the structured filter surface, including degree filters and `include_connected`, but not the newer release's lexical and semantic discovery modes or `semantic_results` payload. |
| `query_graph` | Full Cypher-oriented surface | Shared read-only Cypher parity floor for node and edge reads, filtering, counts, distinct selection, boolean-precedence predicates, numeric property predicates, bounded edge-type conditions, and multi-row ordering already exercised by the shared fixtures | `Near parity` | Yes | The compare harness now proves the `cypher-predicate-floor` slice as an exact Zig/C match and keeps the exercised Go and Java language fixtures inside the scored shared query floor. |
| `trace_call_path` / `trace_path` | Calls, data-flow, cross-service, risk labels, include-tests | Calls, data-flow, cross-service modes; multi-edge-type BFS; risk labels; upstream-default test filtering; function_name alias; structured callees/callers response | `Near parity` | Yes | The exact `snippet-trace-contract` fixture now locks mode defaults, `risk_labels`, `include_tests`, alias handling, and the upstream start-centered flat-edge contract. |
| `get_code_snippet` | Full | Implemented | `Near parity` | Yes | Zig now proves exact shared behavior for exact lookup, basename-style suffix fallback, ambiguity suggestions, and neighbor info on the `snippet-trace-contract` fixture. |
| `get_graph_schema` | Full | Implemented | `Near parity` | Yes | The shared schema floor is now exercised by an exact fixture in diagnostic mode, which keeps the verified overlap honest without pretending payload identity where schema richness still differs. |
| `get_architecture` | Languages, packages, entry points, routes, hotspots, boundaries, layers, clusters, ADR | Shared architecture summary sections, counts, and structured fields aligned on the parity fixtures | `Near parity` | Yes | The `architecture-aspects-parity` fixture now locks the overlapping structure/dependencies/languages/packages/hotspots/entry-points/route/message summary contract; richer original-only clustering sections remain outside this shared row. |
| `search_code` | Graph-augmented grep with ranking/dedup | Shared compact/full/files behavior aligned on the verified parity fixtures, including discovery-scope ignored/generated-file cases and grouped regex/plain-text handling | `Near parity` | Yes | The exact `search-code-ranking-parity` fixture now locks ranking order, full-mode source expansion, files-mode output, deduplication, and grouped alternation handling; implementation-specific enrichment outside the shared floor remains non-scored. |
| `list_projects` | Full | Implemented | `Near parity` | Yes | Exact fixture coverage now locks the shared listing contract while leaving first-gate node and edge counts diagnostic-only. |
| `delete_project` | Full | Implemented | `Near parity` | Yes | Exact fixture coverage now locks the shared delete contract, including the Zig watcher-unregistration path. |
| `index_status` | Full | Implemented | `Near parity` | Yes | Exact fixture coverage now locks the shared indexed/not-found contract instead of relying only on bounded assertions. |
| `detect_changes` | Git diff + impact + blast radius + risk classification, with `since` in `v0.6.0` | Shared git-diff, impacted-symbol, blast-radius, and reporting contract aligned for the parity fixtures, plus direct unit coverage for `since` refs, ISO-date selectors, and invalid-selector errors | `Near parity` | Yes | Zig now exposes the released upstream `since` selector with commit-ish and ISO-date support, while the stale local C comparator still only exercises the older `base_branch` floor. |
| `manage_adr` | Implemented | Implemented with shared `get`, `update`, and `sections` parity | `Near parity` | Yes | The ADR parity fixture remains the exact shared contract lock for this row. |
| `ingest_traces` | Stubbed in original | Stubbed public tool surface is the honest parity target | `N/A` | No | The upstream feature is still not real, but the public tool inventory now matters for exact `tools/list` parity. |

### 2.3 Important Tool-Contract Differences

| Difference | Original C | Zig Port | Why it matters |
|-----------|------------|----------|----------------|
| Indexing argument name | `repo_path` | Public `repo_path`, with `project_path` retained only as a compatibility alias | The public contract should converge on the upstream name while preserving local compatibility during the transition. |
| `search_graph` discovery modes | Regex-style `name_pattern`, BM25 `query`, and vector-backed `semantic_query` | Structured graph search only | Latest-upstream discovery claims are no longer equivalent even though the tool name still overlaps. |
| Trace tool naming | `trace_path` plus `trace_call_path` alias | `trace_call_path` only | The Zig port follows the clearer explicit name. |
| Trace entry argument | `function_name` | `start_node_qn` (with `function_name` alias) | Zig accepts both; prefers qualified name but falls back to name-based search. |
| Trace modes | `calls`, `data_flow`, `cross_service` | `calls`, `data_flow`, `cross_service` | Zig now implements all three trace modes with matching edge type presets. |
| Change baseline selector | `base_branch` or `since` | `base_branch` or `since` | Zig now matches the released latest-upstream baseline-selection contract, but the local full-compare checkout still only exercises the older `base_branch` path. |
| Tools advertised via `tools/list` | 14 total, including stub `ingest_traces` | Tool inventory is converging, but exact schema parity still depends on unresolved latest-upstream contract deltas | Exact tool-surface parity is no longer just a count question; `index_repository.mode` and `search_graph` discovery modes are user-visible parts of the surface. |

## 3. Indexing Pipeline and Graph Construction

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Structure pass | Yes | Yes | `Near parity` | Yes | Both build project/folder/file/module structure. |
| Index modes | `full`, `moderate`, `fast` | `full`, `fast` | `Partial` | No | Zig lacks the upstream `moderate` mode, which is now part of the public indexing contract and the path that enables semantic search without full indexing. |
| Shared target-language definitions extraction | Broad AST extraction across the original language set | Parser-backed extraction aligned with the verified shared Python, JavaScript, TypeScript, Rust, Go, and Java contract, plus Zig-side expansion tranches for C#, PowerShell, and GDScript | `Near parity` | Yes | The parity fixtures now lock shared definition inventory, ownership, and label behavior for the overlapping target languages. The additional Zig-side C#, PowerShell, and GDScript tranche is fixture-verified for parser-backed definitions, but remains a local expansion claim rather than an interoperability claim. |
| Import resolution | Yes, now also persisted as explicit `IMPORTS` graph edges in the `v0.6.0` baseline | Yes, including persisted `IMPORTS` edges on the verified shared slice | `Near parity` | Yes | Zig improved alias preservation and namespace-aware resolution in Phase 4, and the graph-exactness slice now locks shared persisted `IMPORTS` rows directly on the parity fixtures. |
| Shared call-resolution cases | Registry + import-aware resolution + some LSP hybrid paths | Registry + import-aware resolution aligned on the verified alias-heavy shared cases | `Near parity` | Yes | The interop harness now protects the overlapping call-edge contract directly, including the new `typescript-import-cases` fixture. The original's broader LSP-assisted path remains a separate deferred row. |
| Shared usage and type-reference edges | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | Phase 3 now locks the overlapping declaration-time `USAGE` and shared type-reference behavior on the parity fixtures; deeper data-flow remains outside this row. |
| Shared semantic-edge contract | Inherits / decorates / implements and related enrichment | Implemented and aligned for the shared decorator-focused overlap | `Near parity` | Yes | The verified shared contract now matches the original on persisted decorator edges and on the exercised empty-result cases for unsupported inheritance/implements rows. |
| Semantic relatedness / embedding layer | `SEMANTICALLY_RELATED` edges plus vector data that powers `search_graph.semantic_query` in `moderate` / `full` modes | Not implemented | `Deferred` | No | This is the biggest new latest-upstream gap introduced by `v0.6.0`. Zig has lexical FTS5 for `search_code`, but not the upstream semantic-search contract. |
| Qualified-name helpers | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 substrate work. |
| Registry / symbol lookup | Yes | Yes | `Near parity` | Yes | Explicit Phase 2 and Phase 4 work in Zig. |
| Incremental indexing | Yes | Yes | `Near parity` | Yes | Zig persists file hashes and reindexes changed slices. |
| Parallel extraction | Yes | Yes | `Near parity` | Yes | Zig has per-file local buffers plus merge/remap logic. |
| Similarity / near-clone detection | Yes (`SIMILAR_TO`) | Yes (`SIMILAR_TO`) | `Near parity` | Yes | Zig ships MinHash/LSH-based similarity edges in the current contract, and `history-similarity-parity` now locks the shared edge-plus-property row directly. |
| Transactional indexing guardrails | Yes | Yes | `Near parity` | Yes | Zig wraps pipeline writes in transactions and uses an index guard. |
| LSP hybrid type resolution | Present for Go/C/C++ in original | Optional repository sidecar for explicit Go call targets, preferred ahead of heuristic registry matches | `Partial` | No | Zig now accepts `.codebase-memory/hybrid-resolution.json` and proves an expanded bounded Go-backed sidecar contract on reproducible fixtures: the original single-call case plus a multi-document Go slice with `golang` sidecar-language alias support and `callee_name` fallback matching. C/C++ support, compile-commands ingestion, and live LSP client integration remain deferred. |
| Test tagging pass | Yes | Yes for the verified shared Python fixture slice | `Near parity` | Yes | Zig now derives `TESTS` and `TESTS_FILE` from shared filename and call-edge rules on the parity fixture without reopening broader language-specific enrichment work. |
| Git history coupling | Yes | Implemented | `Near parity` | Yes | Zig pass uses subprocess `git log` (no libgit2); `history-similarity-parity` now locks shared `FILE_CHANGES_WITH` rows plus `co_changes` and `coupling_score` properties directly. |
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
| `IMPORTS` | Yes | Yes | `Near parity` | Yes | The shared import-edge contract is now exact-compared on the parity fixtures instead of being inferred indirectly from call resolution. |
| `SIMILAR_TO` | Yes | Yes | `Near parity` | Yes | Landed in Zig Phase 6, and the graph-exactness fixture now compares the shared `jaccard` / `same_file` row directly. |
| `SEMANTICALLY_RELATED` | Yes | No | `Deferred` | No | Upstream `v0.6.0` adds a second semantic-similarity family distinct from MinHash clone detection. |
| Shared `CONFIGURES` contract | Yes | Yes for the verified shared fixture slices | `Near parity` | Yes | The graph-exactness slice now exact-compares the overlapping `CONFIGURES` rows directly, including the graph-model key-symbol normalization case, env-style config variables, and YAML key-shape aliases. |
| Internal serving architecture | Graph-centric serving path | Hybrid internal serving path: SQLite graph core, FTS5 lexical index, optional SCIP sidecar overlay, and query router | `Near parity` | Yes | This is an internal implementation improvement in the Zig port; it deliberately preserves the interoperable MCP surface rather than creating a new client contract. |
| Route and message graph (`Route`, `Channel` in C vs `EventTopic` in Zig, `HTTP_CALLS`, `ASYNC_CALLS`, `HANDLES`, `EMITS`, `LISTENS_ON` in C vs `SUBSCRIBES` in Zig, route-linked data flows) | Yes | Partial | `Partial` | No | Zig now creates concrete URL/path/topic route nodes, verified decorator-backed `HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared async topic caller rows, one additional strict shared `httpx` caller slice, fixture-backed topic nodes, and derived `EMITS` / `SUBSCRIBES` edges with architecture and cross-service trace visibility. The latest upstream release now models channels as `Channel` nodes with `LISTENS_ON`, so the message-edge vocabulary is no longer identical even where the bounded behavior overlaps. |
| Resource / infra graph (`Resource`, K8s/Kustomize entities) | Yes | Not shipped | `Cut` | No | Intentionally outside the Zig scope. |
| `TESTS` / test metadata | Yes | Yes for the verified shared Python fixture slice | `Near parity` | Yes | The graph-exactness slice now exact-compares shared `TESTS` and `TESTS_FILE` rows plus file-level `is_test` metadata for the exercised Python naming rules. |
| `FILE_CHANGES_WITH` | Yes | Yes | `Near parity` | Yes | Zig git-history pass creates `FILE_CHANGES_WITH` edges with `co_changes` and `coupling_score` properties via subprocess `git log`, now exact-compared on the seeded history fixture. |
| Shared `USES_TYPE` contract | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | The graph-exactness slice now exact-compares the overlapping `USES_TYPE` queries directly for the exercised Python, TypeScript, and Rust cases instead of treating them as implicit approximations. |
| `THROWS` / `RAISES` | Yes | Yes for the verified shared fixture slice | `Near parity` | Yes | Zig extracts THROWS/RAISES edges from throw statements (JS/TS/TSX). The graph-exactness slice now exact-compares the shared row on the edge-parity fixture. |
| Remaining long-tail edge families | Yes (broader vocabulary) | Limited to verified slices | `Partial` | No | The remaining or unproven original-overlap edges are `OVERRIDE` (Go-only) and broader positive `WRITES` / `READS` semantics. The public harness now proves bounded shared zero-row `WRITES` / `READS` results across the exercised Python, JavaScript, TypeScript, and local-state micro-cases, while `HANDLES` and route-linked `DATA_FLOWS` already have verified shared route slices. `CONTAINS_PACKAGE` was never implemented in C. |

## 5. Language Support

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Extension / filename detection | Broad, documented as 66 languages | Broad language enum and extension mapping in `src/discover.zig`, plus explicit env-only `CBM_EXTENSION_MAP` overrides | `Near parity` | Yes | Zig detects far more languages than it currently parses deeply, and the operational-controls parity lane now proves `.foo=python` remapping end to end. |
| Tree-sitter-backed definitions across the full language set | Yes | Parser-backed for the verified Python, JavaScript, TypeScript, TSX, Rust, Zig, Go, Java, and C# tranche, but not the full original language set | `Partial` | No | The Zig port now has a broader parser-backed tranche, but it still does not reproduce the original's full language breadth. |
| Tree-sitter-backed definitions for Python | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for JavaScript | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for TypeScript / TSX | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Rust | Yes | Yes | `Near parity` | Yes | Covered by readiness and extractor tests. |
| Tree-sitter-backed definitions for Go | Yes | Yes | `Near parity` | Yes | Zig now extracts Go functions, methods, structs, and interfaces with fixture-backed `go-basic` / `go-parity` coverage, and the exercised shared Go search, query, and trace rows now full-compare cleanly against the C reference. |
| Tree-sitter-backed definitions for Java | Yes | Yes | `Near parity` | Yes | Zig now extracts Java classes, interfaces, constructors, and methods with the `java-basic` fixture, and the exercised shared Java search, query, and trace rows now full-compare cleanly against the C reference. |
| Tree-sitter-backed definitions for C# | Yes | Yes | `Partial` | No | Zig now extracts bounded C# classes, interfaces, constructors, and methods with the `csharp-basic` fixture and direct CLI verification, but this remains a Zig-only parser-backed expansion claim rather than a shared semantic-parity row. |
| Tree-sitter-backed definitions for Zig | Not a headline original language, but supported in the port target | Yes | `Near parity` | No | Zig is a first-class target language in the port. |
| Fallback heuristics for non-target languages | Broad AST extraction in original | Heuristic symbol extraction fallback in Zig | `Partial` | No | Zig intentionally keeps heuristics for unsupported deep-parser languages. |
| Hybrid type/LSP resolution for Go, C, C++ | Yes | No | `Deferred` | No | Explicit original differentiator not currently ported. |

## 6. Runtime and Operations

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Default stdio MCP server | Yes | Yes | `Near parity` | Yes | This is the default mode in both entrypoints, and Zig now has explicit `1 MiB` request-line and `4 MiB` response-envelope guardrails validated by unit tests plus the runtime harness. |
| Persistent runtime cache / DB | Yes | Yes | `Near parity` | Yes | Zig now proves cache-root selection through `CBM_CACHE_DIR`, Windows `LOCALAPPDATA`, Windows no-`HOME` fallback via `USERPROFILE` / `HOMEDRIVE` + `HOMEPATH`, Unix `XDG_CACHE_HOME`, and `HOME` fallback behavior via fixture-backed installer and runtime checks. |
| Watcher-driven auto-reindex | Yes | Yes | `Near parity` | Yes | Both use git-based watcher logic. |
| Startup auto-index | Yes | Yes | `Near parity` | Yes | Zig now has a direct startup test for indexing the current temp repo and registering it with the watcher, in addition to the long-running runtime harness coverage around the surrounding stdio lifecycle. |
| Previously indexed project watcher registration | Yes | Yes | `Near parity` | Yes | Zig now has a focused startup test for `registerIndexedProjects`, which watches only persisted projects with real roots before the long-running watcher thread starts. |
| UI runtime flags (`--ui`, `--port`) | Yes | No | `Cut` | No | Zig does not ship the UI server. |
| Startup update notification | Yes | Yes, one-shot notice on the first post-initialize response | `Near parity` | Yes | Zig now starts an update check on `initialize`, preserves the pending notice until it can be injected safely, and covers the env-override plus one-shot behavior in the runtime harness, including the `notifications/initialized` path staying silent before the first real tool response. |
| Benchmarking / soak / security scripts | Present | Repo-owned benchmark, soak, and static audit scripts plus CI wiring | `Partial` | No | Zig ships `scripts/run_benchmark_suite.sh`, `scripts/run_soak_suite.sh`, `scripts/run_security_audit.sh`, maintainer docs, and `.github/workflows/ops-checks.yml`. Verified on `2026-04-19`: Zig-only benchmark medians were `1340.308 ms` on `self-repo` and `72.769 ms` on `sqlite-amalgamation`, the soak suite reported `303.966 ms` p95 indexing over four iterations, and the static audit passed `17` checks with `0` failures. The latest-upstream operational surface is still broader because binary-string auditing, runtime network-trace auditing, fuzzing, and longer-duration soak coverage remain outside this repo's bounded suite. |

## 7. CLI and Productization

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Shared `install` flow (`Codex CLI` / `Claude Code`) | Yes | Yes | `Near parity` | Yes | The temp-HOME CLI parity harness proves the overlapping install reporting and config-file effects for the two shared agent targets, the Zig CLI now makes both the shipped scope and MCP-only side-effect behavior explicit, and the Windows lane now proves install succeeds with `HOME` unset when `USERPROFILE`, `APPDATA`, and `LOCALAPPDATA` are present. |
| Shared `uninstall` flow (`Codex CLI` / `Claude Code`) | Yes | Yes | `Near parity` | Yes | The same temp-HOME parity harness locks the overlapping uninstall behavior, including dry-run preservation and dual Claude config cleanup, while the Zig CLI now defaults uninstall scope to the shipped agent set and can skip extra side effects with `--mcp-only`. |
| Shared `update` flow (`Codex CLI` / `Claude Code`) | Yes, release-oriented updater plus config refresh | Yes, shared config refresh plus a verified file-backed packaged-archive self-replacement path on supported Unix and macOS hosts | `Near parity` | Yes | Phase 4 still proves the overlapping config-refresh and reporting contract, and plan 09 adds a temp-home self-update lane driven by configured `download_url` plus packaged release fixtures. The remaining delta is broader network-backed updater behavior and the original's wider packaging surface, not the bounded local self-replacement path now under test. |
| `config` | Yes | Yes | `Near parity` | Yes | Zig now supports persisted config for `auto_index`, `auto_index_limit`, `idle_store_timeout_ms`, `update_check_disable`, `install_scope`, `install_extras`, and `download_url`, with temp-home fixture evidence for `set`, `get`, `list`, and `reset` on the operational controls it exposes today; env-only `CBM_EXTENSION_MAP` is verified separately through the same parity harness. |
| `cli --progress` | Yes, rich progress sink | Yes, shared phase-aware parity stream for overlapping commands | `Near parity` | Yes | Verified by the interop harness temp-HOME CLI check, which now reports `cli_progress: match`. |
| Auto-detected shared agent integrations | 10 agents total, including Codex CLI and Claude Code | 10 detected-scope agent targets now covered in the temp-home installer matrix | `Near parity` | Yes | The expanded temp-home harness now proves the broader detected-scope matrix and CLI reporting for Codex CLI, Claude Code, Gemini, Zed, OpenCode, Antigravity, Aider, KiloCode, VS Code, and OpenClaw, while the shipped default scope stays intentionally narrower. |
| Agent instructions / skills / hooks installation | Yes | Yes, with one consolidated Claude skill package instead of the original multi-skill layout | `Partial` | No | Zig now installs the broader instruction, hook, reminder, and rules side effects in the detected-scope matrix. The remaining material delta is the consolidated Claude skill packaging rather than the original four-skill layout. |
| Manual agent config support | Yes | Yes for the broader 10-agent detected-scope matrix | `Near parity` | Yes | The expanded temp-home harness now proves config writes and removals across Codex CLI, Claude Code, Gemini, Zed, OpenCode, Antigravity, KiloCode, VS Code, and OpenClaw, with PATH-based Aider instruction handling covered separately in the same lane. |

## 8. Build, Packaging, and Repository Shape

| Capability | Original C | Zig Port | Status | Interoperable? | Notes |
|-----------|------------|----------|--------|----------------|-------|
| Primary build system | Make + shell scripts | `zig build` plus repo-owned packaging, manifest emission, and release-validation scripts | `Partial` | No | Both repos now ship build and release scaffolding. The remaining difference is that Zig intentionally packages only the standard binary surface, not the original UI-oriented release variants or external trust layers. |
| Setup scripts | Yes (`scripts/setup.sh`, `setup-windows.ps1`) | Yes (`install.sh`, `install.ps1`, `scripts/setup.sh`, `scripts/setup-windows.ps1`) | `Near parity` | Yes | Zig now verifies both shell and PowerShell entrypoints against local packaged archives, with manifest-backed archive verification when `release-manifest.json` is present, while keeping the scope on the standard binary rather than the original's broader UI release set. |
| UI asset embedding | Yes | No | `Cut` | No | Tied to the UI subsystem. |
| Security / audit / benchmark script set | Broad script suite | Bounded repo-owned benchmark, soak, and static audit suite | `Partial` | No | Zig provides reproducible local and CI entrypoints for benchmark, soak, and static audit coverage. It intentionally stops short of the original's binary-string, network-trace, fuzz, and multi-hour soak layers, so this row should not keep a parity-positive label. |
| Interop harness against the original | Not applicable | Yes | `Near parity` | No | This is a Zig-side advantage for tracking compatibility over time. |

## 9. What the Zig Port Can Truthfully Claim Today

| Claim | Assessment |
|------|------------|
| It is a useful daily-use MCP server for structural code intelligence | Yes |
| It matches the original on the documented readiness gate | Yes |
| It implements the completed post-readiness target contract described in this repo | Yes |
| It is near-parity with the latest upstream `v0.6.0` release | No |
| It is a full feature-for-feature port of the original C project | No |
| Its automated suite is exhaustive of all implemented features and edge cases | No |
| It has no meaningful remaining work in its chosen daily-use target | Yes |
| It still has optional future parity work if exhaustive comparison is the goal | Yes |

## 10. Biggest Remaining Differences

If someone asks “what still separates the Zig port from the original?”, the shortest accurate answer is:

| Difference | Why it matters |
|-----------|----------------|
| No exhaustive Cypher parity | The verified shared floor now covers node and edge reads, filters, counts, distinct selection, boolean-precedence predicates, numeric property predicates, and bounded edge-type conditions, but more advanced graph-query permutations such as deeper multi-hop shapes, richer aggregates, aliases, and skip-style pagination remain unproven or C-only. |
| Broader route / cross-service framework expansion | Zig now emits verified decorator-backed `HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared async topic caller rows, route summaries, and one additional strict shared `route-expansion-httpx` caller fixture beyond the original graph-model route slices. The broader keyword route-registration, generic `requests.request("METHOD", "/path")`, and `celery.send_task("topic")` fixtures remain diagnostic-only in the full compare because the current C reference still returns empty row sets there, so broader shared-framework parity remains open. |
| No LSP-assisted hybrid resolution | Some higher-fidelity call/type resolution paths remain original-only. |
| Broader config normalization expansion | Git-history coupling is implemented, config linking has dependency-import matching and deduplication coverage, a strict shared key-symbol normalization fixture, a strict shared env-style config-key fixture, and a strict shared YAML key-shape fixture. Broader config-language and key-shape expansion remains optional future work, while `WRITES` / `READS` still have only a bounded shared zero-row harness contract across the exercised parity micro-cases rather than proven positive overlap. |
| No UI subsystem | The original can run a graph visualization UI; the Zig port intentionally cannot. |
| Installer ecosystem still differs | The Zig port now proves the broader 10-agent detected-scope matrix, hooks, reminders, instructions, a bounded file-backed self-update path, and the Windows no-`HOME` path-root fallback contract, but it still keeps the shipped default scope narrower, consolidates the Claude skill layout, and stops short of broader network-backed updater, release-trust behavior, and full native Windows process or archive parity. |

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
