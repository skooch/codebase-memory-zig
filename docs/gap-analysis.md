# Gap Analysis: Zig Port vs C Original

What the C codebase has that the Zig port does NOT yet have. Excludes deliberately cut features (see zig-port-plan.md Section 2 "CUT" list).

Status key: **WORKS** (implemented for the current target contract), **STUB** (type signatures exist, no implementation), **MISSING** (not present at all), **PARTIAL** (some logic, incomplete)

For the most readable current-state comparison against the original implementation, see:
- [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md)

The detailed subsystem tables below are historical backlog references. When a table entry disagrees with the current snapshot, treat the current snapshot and [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md) as authoritative, and update the table during the next focused phase for that subsystem.

## Current Snapshot

Completed now:
- The first interoperability-readiness gate is complete.
- The readiness-scope tool surface is implemented and exercised:
  - `index_repository`
  - `search_graph`
  - `query_graph`
  - `trace_call_path`
  - `list_projects`
- The broader day-to-day MCP surface added after readiness is now implemented:
  - `get_code_snippet`
  - `get_graph_schema`
  - `get_architecture`
  - `search_code`
  - `delete_project`
  - `index_status`
  - `detect_changes`
- Parser-backed definition extraction is working for the readiness languages:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
- The first-gate fixture harness baseline is:
  - `Strict matches: 58`
  - `Diagnostic-only comparisons: 9`
  - `Mismatches: 0`
- The expanded full harness after graph-model parity currently reports:
  - `Fixtures: 24`
  - `Comparisons: 186`
  - `Strict matches: 105`
  - `Diagnostic-only comparisons: 24`
  - `Known mismatches: 8`
  - `cli_progress: match`
  - no remaining route-related or graph-model fixture mismatches

Completed after the readiness gate:
- Runtime lifecycle and scale baseline:
  - watcher-driven auto-index and auto-reindex
  - incremental indexing
  - parallel extraction and graph-buffer merge
  - MinHash/LSH similarity edges
  - signal-driven graceful shutdown for stdio MCP sessions
  - one-shot startup update notification on the first post-initialize response
  - timed idle runtime-store eviction plus reopen on the next stdio tool call
- CLI and productization baseline:
  - persisted runtime config
  - `install`, `uninstall`, `update`, and `config`
  - `cli --progress`
  - installer support for Codex CLI and Claude Code
- Shared Phase 2 protocol/query parity slice:
  - `tools/list`
  - `cli --progress`
  - `query_graph`
  - `get_architecture`
  - `search_code`
  - `detect_changes`
  - verified by `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh`
  - current evidence: `Comparisons: 67`, `Strict matches: 58`, `Diagnostic-only comparisons: 9`, `Mismatches: 0`, `cli_progress: match`
- Hybrid serving baseline without MCP contract drift:
  - `SQLite` remains the canonical graph store
  - `FTS5` now backs lexical candidate generation in `search_code`
  - optional `.codebase-memory/scip.json` sidecars can import precise overlay facts into local overlay tables
  - `src/query_router.zig` now routes `search_code`, `get_code_snippet`, `get_architecture`, and `detect_changes` to the appropriate internal substrate while preserving the existing MCP tool surface
  - current evidence: `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh`, and `bash scripts/run_benchmark_suite.sh` all pass in the hybrid-serving worktree

Intentionally deferred after Phase 7:
- The remaining MCP work outside the completed daily-use slice, especially fuller Cypher parity.
- Full Cypher parity beyond the broader day-to-day query subset now supporting node/edge reads, filtering, sorting, and counts.
- Deeper usage/type-reference extraction parity and broader cross-language semantics beyond the current target daily-use slice.
- Richer decorator/enrichment follow-ons and broader route/config expansion beyond the implemented graph-model parity fixture contract. (Git-history coupling is implemented; route nodes and config-linking both have strict shared graph-model fixture slices.)
- Broader installer/self-update behavior beyond the current source-build-friendly Codex CLI / Claude Code support.

Completed in Plan 03:
- Advanced trace parity: modes (calls/data_flow/cross_service), multi-edge-type BFS, risk labels, test-file filtering, function_name alias, structured callees/callers response format.

Completed in Plan 05:
- Long-tail edge parity: `THROWS`/`RAISES` edges from throw statements (JS/TS/TSX). Verified end-to-end on the edge-parity fixture with RAISES resolving custom error classes. Out-of-scope edges: `OVERRIDE` (Go-only), `CONTAINS_PACKAGE` (never implemented in C), `WRITES` and `READS` (not proven original-overlap by the current C reference fixture).

## In-Progress Plan: Operational Controls and Configurability

Current control-surface inventory from the Zig implementation:

- persisted config keys
  - `auto_index`
  - `auto_index_limit`
  - `download_url`
- path and config-root overrides
  - `CBM_CONFIG_PLATFORM`
  - `CBM_CACHE_DIR`
  - `LOCALAPPDATA`
  - `APPDATA`
  - `XDG_CACHE_HOME`
  - `XDG_CONFIG_HOME`
- runtime and lifecycle overrides
  - `CBM_AUTO_INDEX`
  - `CBM_AUTO_INDEX_LIMIT`
  - `CBM_IDLE_STORE_TIMEOUT_MS`
  - `CBM_UPDATE_CHECK_DISABLE`
  - `CBM_UPDATE_CHECK_LATEST`
  - `CBM_UPDATE_CHECK_CURRENT`
  - `CBM_UPDATE_CHECK_URL`
- operator-facing controls already present
  - `cbm config list|get|set|reset`
  - `cbm cli --progress`
  - installer action flags: `-y`, `-n`, `--dry-run`, `--force`
  - explicit installer scope: `--scope shipped|detected`
- persisted runtime controls added in this worktree
  - `idle_store_timeout_ms`
  - `update_check_disable`

Known gaps this plan is targeting:

- host bind/listen controls are not part of the current Zig operational
  surface, so they need to be treated as absent rather than assumed.
- installer scope is still effectively fixed to the currently shipped agent set
  instead of exposing an explicit operator-controlled target matrix.
- runtime and config knobs are spread across `src/cli.zig`, `src/main.zig`,
  and `src/runtime_lifecycle.zig`, which makes precedence and verification less
  obvious than it should be.
- there is not yet a dedicated fixture-backed configuration lane under
  `testdata/interop/configuration/` that exercises these knobs without touching
  a real home directory.

Phase 1 evidence:

- the plan is now active at
  [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/operational-controls-and-configurability-feature-cluster-plan.md)
- the progress log and fixture placeholder now live at
- the current branch now proves persisted `config set|get|list|reset` handling
  for `idle_store_timeout_ms` and `update_check_disable` through the temp-home
  `operational_contract` lane in `scripts/run_cli_parity.sh --zig-only`
- the current branch now makes the CLI install/update/uninstall scope explicit:
  - default CLI scope is `shipped`
  - `--scope detected` is the explicit broader detected-agent path
- the progress log, fixture placeholder, and current configuration matrix now
  live at
  [operational-controls-and-configurability-feature-cluster-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/operational-controls-and-configurability-feature-cluster-progress.md)
  ,
  [configuration-matrix.md](/Users/skooch/projects/codebase-memory-zig/docs/configuration-matrix.md),
  and
  [testdata/interop/configuration/env-overrides/README.md](/Users/skooch/projects/codebase-memory-zig/testdata/interop/configuration/env-overrides/README.md)

## Implemented Plan: Windows, Installer, and Client Integration

Current matrix for the completed slice:
- runtime cache root selection
  - `CBM_CACHE_DIR`
  - Windows `LOCALAPPDATA`
  - Unix `XDG_CACHE_HOME`
  - `HOME` fallback
- roaming config root selection
  - Windows `APPDATA`
  - Unix `XDG_CONFIG_HOME`
  - macOS `~/Library/Application Support`
- client config targets under test
  - Codex CLI
  - Claude Code
  - Zed
  - VS Code
  - KiloCode
- startup checks to preserve while installer path logic changes
  - `initialize`
  - one-shot `update_notice`
  - EOF and SIGTERM shutdown

Completion evidence:
- `src.cli.runtimeCacheDir` now accepts an explicit config-platform override and
  resolves Windows `LOCALAPPDATA`, Unix `XDG_CACHE_HOME`, and the existing
  `CBM_CACHE_DIR` / `HOME` fallback behavior through one shared helper layer.
- `src.cli.detectAgents` and the Zed, VS Code, and KiloCode install helpers now
  route through shared config-platform path helpers instead of deriving paths
  only from the host OS tag, which makes Windows-layout checks reproducible on
  a non-Windows host.
- `scripts/run_cli_parity.sh --zig-only` now seeds fixture-backed Windows
  layouts under `APPDATA` / `LOCALAPPDATA` and verifies the Zig installer and
  runtime-config paths there.
- `src.mcp.handleLine` now ignores no-`id` notifications, and the runtime
  harness proves `notifications/initialized` stays silent while the first real
  tool response still receives the one-shot update notice.

## Implemented Plan: Large-Repo Reliability and Crash Safety

Known current-state evidence from the Zig implementation:
- `src.pipeline.collectExtractionsParallel` allocates a `results` slot for every
  discovered file and keeps every successful extraction resident until the join
  phase completes, so extraction itself still scales with whole-file-set width
  even though the later persistence path now releases that memory earlier.
- `src.pipeline.run` / `runIncremental` now defer `BEGIN IMMEDIATE` until the
  actual write phase and release owned extractions before graph-store writes and
  search-index refresh, which bounded the writer-lock window under the local
  stress lanes.
- `src.graph_buffer.loadFromStore` / `dumpToStore` now enforce explicit graph
  size caps before bulk allocation or SQLite writes begin, so oversized graphs
  fail observably instead of relying on implicit "average repo" assumptions.
- `src.mcp.runFiles` now caps newline-framed requests at `1 MiB`, and MCP
  success envelopes are capped at `4 MiB`, so request and response framing now
  fail with deterministic JSON-RPC errors instead of silent truncation.
- `src.watcher.pollOnce` now snapshots due work under lock and performs git
  probes and index callbacks outside the mutex, so slow watcher work no longer
  blocks the whole watcher state machine under lock.
- `src.runtime_lifecycle.injectUpdateNoticeBounded` now preserves pending update
  notices when a response cannot safely accept them yet, instead of dropping
  lifecycle metadata on error or oversized-response paths.

Phase 1 contract for this plan:
- Treat memory growth, oversized request buffering, and bulk graph-store writes
  as explicit stress-contract surfaces rather than incidental implementation
  details.
- Treat watcher and runtime lifecycle determinism under slow or failing work as
  correctness requirements, not best-effort behavior.
- Treat local stress fixtures and bounded verification thresholds as completion
  gates before upgrading any large-repo stability claims.

## Implemented Plan: Runtime Lifecycle Extras

Known current-state evidence from the Zig implementation:
- `src.main.runMcpServer` now wires the shared runtime DB path and idle timeout
  into the MCP server, with `CBM_IDLE_STORE_TIMEOUT_MS` available for bounded
  verification runs.
- `src.mcp.runFiles` now polls stdio with an idle timeout and closes the shared
  runtime SQLite handle after inactivity instead of keeping the runtime DB open
  indefinitely for the entire session.
- `src.mcp.handleLine` now reopens that shared runtime DB on the next
  `tools/call` request before dispatch, so session queries resume cleanly after
  an idle eviction without changing the public MCP contract.
- `scripts/test_runtime_lifecycle_extras.sh` now proves the live stdio process
  closes the runtime DB after idling and reopens it on the next tool call, and
  `src.mcp` has a focused unit test for the same reopen path.

Phase 1 contract for this plan:
- Treat the remaining runtime gap as idle store lifecycle behavior, not as a
  reason to reopen the already-completed shutdown or update-notice work.
- Treat the public overlap as release-and-reopen behavior on the shared Zig
  runtime DB; the original C runtime's per-project cached-store topology is an
  internal implementation difference rather than a contract requirement here.
- Require live-process verification of the idle close/reopen cycle before
  upgrading the runtime-extras parity claim.

Completion evidence:

- `zig build`
- `zig build test`
- `bash scripts/test_runtime_lifecycle.sh`
- `bash scripts/test_runtime_lifecycle_extras.sh`

## Implemented Plan: Parser Accuracy and Graph Fidelity

Known current-state evidence from the Zig implementation:
- `src/extractor.zig:extractFile` still combines tree-sitter-backed definitions
  with line-by-line fallback parsing and module-level ownership defaults.
- Route metadata, imports, calls, usages, and throws are still accumulated from
  line parsing before later resolution, which is where owner drift and
  false-positive attachment can still occur.
- `src.registry.addImportBinding` already preserves alias and namespace hints,
  and the current accuracy fixtures now prove that the shared Python
  decorator-backed `HANDLES` contract and the shared TypeScript alias-aware call
  surface are stable on the refreshed branch tip.

Phase 1 bucket map for the parser-accuracy tranche:

| Bucket | Upstream issue families | Why it belongs here | Phase 1 fixture lane |
|--------|--------------------------|---------------------|----------------------|
| Current target-language correctness | `#5`, `#6`, `#7`, `#8`, `#26`, `#43`, `#180`, `#236` | These overlap the parser-backed Python/JS/TS surface the Zig port already claims today: symbol ownership, false route signals, and import-aware resolution. | `python-framework-cases`, `typescript-import-cases` |
| Deferred unsupported-language parity | `#9`, `#218`, `#219`, `#223` | These depend on unsupported or not-yet-parser-backed language surfaces such as C++, R, and embedded Svelte/Vue script extraction. Keep them as explicit deferred fixtures instead of silently mixing them into current-language claims. | `cpp-resolution-cases`, `r-box-cases`, `svelte-vue-import-cases` |
| Future semantic-graph expansion | `#27`, `#28`, `#29`, `#55`, `#56`, `#220`, `#228` | These require broader route-graph, indirect-call, or higher-order semantic expansion rather than a narrow correctness repair to the currently shipped contract. | Document only in this plan; implement later in the semantic-graph expansion cluster |

Phase 1 contract for this plan:
- Keep module-vs-function ownership, false route detection, and import-aware
  resolution in scope for already-supported languages.
- Treat unsupported-language and embedded-script reports as deferred lanes that
  still get local fixtures and explicit documentation.
- Do not expand the broader semantic graph in this plan; only record the cases
  that belong to later route or indirect-call work.

Completion evidence:

- `python-framework-cases`
  - shared `search_graph` and `query_graph(HANDLES)` assertions now match
    between Zig and the current C reference in `scripts/run_interop_alignment.sh`
- `typescript-import-cases`
  - shared `search_graph` and `trace_call_path` assertions now match in the
    interop harness
  - direct Zig CLI tracing from `run` reaches `markStart`, `parsePayload`, and
    `handleRequest`, which is stronger than the current shared harness floor
- Deferred unsupported-language lanes remain explicitly deferred:
  - `cpp-resolution-cases`
  - `r-box-cases`
  - `svelte-vue-import-cases`

## Completed Shared Capability Full-Parity Follow-On

Phase 2 of the follow-on parity plan is now complete: `cli --progress`, `query_graph`, `get_architecture`, `search_code`, and `detect_changes` are now backed by green shared-capability evidence and can be marked `Interoperable? Yes` in [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md).

The historical rows below describe the acceptance targets used by completed shared-capability work or optional deferred follow-ons. Do not read this table as the active plan inventory; the active backlog lives under `docs/plans/new/`, while the completed graph-model parity entrypoint lives under `docs/plans/implemented/`.

| Capability row | Current gap | Full-parity acceptance rule | Primary Zig files | Verification target |
|----------------|-------------|-----------------------------|-------------------|---------------------|
| Definitions extraction | Zig reaches daily-use fidelity but not full shared overlap | For already-overlapping target languages, the Zig extractor emits the same symbol labels, names, nesting roles, and declaration retention as the original on parity fixtures | `src/extractor.zig`, `src/pipeline.zig` | Extractor tests plus interop fixture comparisons |
| Call resolution | Zig misses some shared alias-heavy and suffix-heavy cases | The Zig pipeline resolves the same overlapping call edges as the original on parity fixtures with aliasing and cross-file imports | `src/registry.zig`, `src/pipeline.zig` | Pipeline tests plus interop trace/search assertions |
| Usage / type-reference edges | Zig has useful `USAGE` output but not full shared parity | The Zig graph emits the same overlapping usage and type-reference facts as the original where both implementations already model them | `src/extractor.zig`, `src/pipeline.zig`, `src/store.zig` | Pipeline/store tests plus parity fixture graph queries |
| Semantic edges | Zig covers a narrower semantic slice | The Zig graph emits the same overlapping `INHERITS`, `IMPLEMENTS`, and `DECORATES` facts as the original on shared target-language fixture cases | `src/extractor.zig`, `src/pipeline.zig`, `src/store.zig` | Pipeline tests plus parity fixture graph queries |
| `CONFIGURES` / `USES_TYPE` | `CONFIGURES` and `USES_TYPE` are at shared-fixture parity; `WRITES` is not currently proven original-overlap by the C reference fixture | The Zig graph emits the same overlapping edge families, target resolution, and retained metadata as the original on parity fixtures that exercise config files and type references | `src/extractor.zig`, `src/pipeline.zig`, `src/graph_buffer.zig`, `src/store.zig` | Parity fixtures plus interop graph/query comparisons |
| `THROWS` / `RAISES` | Zig now extracts throw/raise edges for JS/TS/TSX | The Zig graph emits `THROWS` and `RAISES` edges from throw statements with the same checked/unchecked classification heuristic as the original | `src/extractor.zig`, `src/pipeline.zig` | Edge-parity fixture plus store tests |
| `install`, `uninstall`, `update` | Zig implements the commands with a narrower source-build workflow | The Zig CLI matches the original overlapping behavior for shared agent targets, config persistence, reporting, and reversible filesystem changes in temp-HOME tests | `src/cli.zig`, `src/main.zig` | Temp-HOME command parity checks against both CLIs |
| Auto-detected agent integrations | Zig detects only Codex CLI and Claude Code | The Zig CLI auto-detects every shared agent target it claims to support in the same environments and reports the same selection behavior as the original | `src/cli.zig` | Temp-HOME detection matrix tests plus CLI output comparison |

Review-validated notes for graph-fidelity follow-ons:
- Self-call suppression and silent relation-insertion failure handling were correctness bugs and have been fixed in the relation layer.
- Python module-vs-function `USAGE` ownership drift is not currently treated as a bug fix target; it remains contract-design work until the repo defines a sharper ownership rule for `USAGE` and any future `USES_TYPE` split.
- Broader TypeScript and Rust type-reference drift is likewise deferred as graph-contract work rather than something to “correct” toward the original implementation’s narrower output.
- `Constant` remains an intentional Zig label and should not be collapsed into `Variable` purely for source resemblance.

## Remaining Implementation Plan

Complete slices:
- First-gate interoperability readiness plan
- Readiness-scope extractor/pipeline/registry/store/MCP vertical slice
- First fixture corpus and alignment harness
- Post-readiness execution Phases 2-7
- Runtime lifecycle and scale baseline
- CLI/productization baseline for the current target contract

Deferred or optional future slices:
- Public surface expansion:
  - trace breadth now covers modes, risk labels, and multi-edge-type filtering (Plan 03 complete); `HTTP_CALLS` and `ASYNC_CALLS` edges are now produced via service-pattern call reclassification, decorator-backed `HANDLES` edges are verified on the graph-model route fixture, route-linked `DATA_FLOWS` now has a strict shared C/Zig fixture row, and async topic routes now have a strict shared fixture row
- Query/runtime expansion:
  - full Cypher lexer/parser/executor parity beyond the verified shared read-only floor
  - broader traversal and query-analysis parity beyond the current shared `detect_changes` contract
- Indexing/runtime expansion:
  - deeper usage/type-ref extraction parity beyond the current daily-use slice
- Metadata and enrichment:
  - git-history coupling — now implemented (subprocess `git log`, `FILE_CHANGES_WITH` edges)
  - long-tail edges — now implemented: `THROWS`/`RAISES` (JS/TS/TSX throw statements), decorator-backed `HANDLES`, and route-linked `DATA_FLOWS`; remaining or out-of-scope gaps: `OVERRIDE` (Go-only), `WRITES`/`READS` (not proven original-overlap by the current C reference fixture)
  - route nodes — implemented for the graph-model parity fixture contract plus the completed `route-expansion-httpx` follow-on fixture (stub and concrete URL/path/topic `Route` nodes, verified decorator-backed `Route`/`HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared `ASYNC_CALLS`, route summary exposure, and one additional strict shared `httpx` caller slice; unsupported framework-registration probes remain documented future work)
  - config-linking — implemented for the graph-model parity fixture contract plus the completed `config-expansion-env-var-python` follow-on fixture (Strategy 1 key-symbol + Strategy 2 dependency-import, strict shared key-symbol normalization fixture, raw-key preservation, `CONFIGURES` query visibility, Zig dependency-import deduplication coverage, and one additional strict shared env-style config-key slice; `WRITES` / `READS` remain unproven public-harness rows)
  - richer decorator/enrichment promotion
  - completed entrypoint: [graph-model-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/graph-model-parity-plan.md)
- Productization beyond the current contract:
  - broader installer/self-update behavior
  - broader agent integration coverage and installer diagnostics

### Recommended Sequencing

If future work is promoted out of the deferred bucket, use this order:

1. **Shared substrate first**
   - store/search/traversal/schema helpers
   - graph-buffer completion
   - registry/FQN strengthening
2. **Low-risk public surface second**
   - tools that mostly expose existing graph data
3. **Graph fidelity third**
   - extraction, call/import resolution, usages, semantic edges
4. **Heavy analysis surface fourth**
   - fuller search/Cypher/architecture/detect-changes work
   - status: complete for the current daily-use slice
5. **Lifecycle and scale fifth**
   - watcher, incremental indexing, parallel extraction, similarity
6. **Selective deferred features last**
   - promote only the deferred features that still make sense after the core runtime settles

This order is recommended because it maximizes shared reuse, keeps early verification cheap, and avoids layering concurrency or installer behavior on top of still-moving indexing semantics.

## Note On Detailed Matrix

The detailed subsystem matrix below predates the completed readiness milestone and much of the completed post-readiness work.

Read it as:
- a historical backlog inventory
- a rough subsystem checklist for future follow-on work

Do not read it as:
- the current shipped status of the Zig port
- the authoritative parity comparison with the original

For the current complete-vs-deferred split, use:
- the snapshot and plan sections above
- [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md)
- `docs/plans/implemented/shared-capability-parity-plan.md` for the completed shared-surface full-parity execution plan

The rows below intentionally preserve the original audit wording, including
many `STUB` / `MISSING` labels that are no longer current after later
implementation phases.

---

## Archived Initial Readiness Alignment Scope

For the first interoperability pass, this subset was evaluated:

- `index_repository`
- `search_graph`
- `query_graph`
- `trace_call_path`
- `list_projects`

Parser-backed extraction behavior for this gate:

- `extractor` uses tree-sitter for:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
- Heuristic symbol extraction remains only for languages where tree-sitter support is not yet wired.
- Deferred or intentionally partial parser parity for the first gate:
  - member function/class method call target inference
  - deep import/namespace resolution across mixed project-relative paths
  - some advanced trait/impl edge cases
  - non-target language feature extraction

Comparator assumptions for this scope:

- Path values are normalized to `/`.
- Tool output order is treated as deterministic once normalized:
  - `search_graph`: name, file path, qualified name.
  - `query_graph`: column and row order as returned by the execution result.
  - `trace_call_path`: edge order is treated as an unordered set for first-pass comparison.
  - `list_projects`: sorted by project name.
- Count-style query column aliases such as `count` and `COUNT(n)` are normalized to `count` for fixture comparisons.
- Internal IDs, watcher callbacks, and deferred/missing modules are ignored unless explicitly promoted.
- `index_repository` and `list_projects` node/edge totals are retained in the baseline report for diagnostics, but they are not hard-fail fields in the readiness gate once the tool call succeeds and the fixture project is present.
- CUT and DEFER sections in the larger plan are out-of-scope for mismatch scoring during this gate.

#### Readiness diff tolerance

- **Accepted differences**
  - Unstable numeric IDs in response payloads (`nodes.id`, trace edge IDs) are not compared.
  - Path separator normalization differences (`\\` vs `/`) are normalized before comparison.
  - Tool behavior differences limited to the first gate scope are allowed if they are documented in the current docs.
  - Extra `search_graph` rows are tolerated when the fixture's required symbols are still present for the exercised filter.
  - Extra non-`CALLS` edges in `trace_call_path` are accepted while the traversal remains direction/depth-consistent.
- **Hard failures**
  - Missing expected nodes/edges for supported symbols in `search_graph`.
  - Missing or malformed `index_repository` project metadata for the same project path and mode.
  - `query_graph` schema mismatch after normalization (`columns` order/content or row set mismatch).
  - `list_projects` missing `name`, `indexed_at`, or `root_path` after normalization.

---

## MCP Server (`mcp.zig` vs `mcp/mcp.c`)

The Zig stub has the 14 tool names as an enum but zero handler implementations.

| Tool | C Status | Zig Status | Complexity |
|------|----------|------------|------------|
| `index_repository` | Full (full/fast modes, cancellation, lock, auto-index) | WORKS | High — remaining gap is broader contract parity, not basic availability |
| `search_graph` | Full (regex, degree filter, pagination, sort, include_connected, exclude_entry_points) | STUB | High — complex query builder with 12+ parameters |
| `query_graph` | Full (Cypher lex/parse/execute, max_rows, project filter) | STUB | High — depends on Cypher engine |
| `trace_call_path` | Full (BFS, inbound/outbound/both, edge type filter, depth, risk classification) | WORKS (modes, multi-edge-type, risk labels, test filtering) | Medium — BFS + store queries |
| `get_code_snippet` | Full (exact QN + fuzzy name, include_neighbors, source file read) | STUB | Medium — store lookup + file I/O |
| `get_graph_schema` | Full (label/type counts, relationship patterns, samples) | STUB | Low — aggregate SQL queries |
| `get_architecture` | Full (languages, packages, entry points, routes, hotspots, Louvain clusters, layers, file tree, ADR) | STUB | High — many aggregate queries, clustering |
| `search_code` | Full (grep + graph enrichment, dedup into functions, rank by importance, compact/full/files modes) | STUB | High — needs grep subprocess + graph join |
| `list_projects` | Full (name, node/edge counts, indexed_at, root_path) | STUB | Low |
| `delete_project` | Full (cascade delete nodes/edges, remove .db file, unwatch) | WORKS | Low |
| `index_status` | Full (in_progress/complete, node/edge counts) | WORKS | Low |
| `detect_changes` | Full (git diff → affected symbols, blast radius via BFS, risk levels) | STUB | High — git diff parsing + store queries + BFS |
| `manage_adr` | Full (get/update/sections modes, section parsing/rendering, validation) | WORKS for the shared `get` / `update` / `sections` contract; deeper validation helpers remain follow-on work | Medium |
| `ingest_traces` | Stub in C too ("not yet implemented") | STUB | N/A — cut feature |

**Historical initial gap:** 13 tool handlers to implement (excluding
`ingest_traces`, which was cut).

### MCP Protocol Layer

| Feature | C Status | Zig Status |
|---------|----------|------------|
| JSON-RPC 2.0 parsing (id, method, params) | Full (`cbm_jsonrpc_parse`) | STUB — `handleLine` returns null |
| JSON-RPC response formatting | Full (`cbm_jsonrpc_format_response/error`) | MISSING |
| MCP initialize handshake | Full (protocol version negotiation, capabilities) | MISSING |
| MCP tools/list response | Full (14 tool schemas with descriptions, parameter types) | MISSING |
| Tool argument extraction (string, int, bool) | Full (`cbm_mcp_get_*_arg`) | MISSING |
| MCP text result formatting | Full (`cbm_mcp_text_result`) | MISSING |
| Session/startup auto-index wiring | Full (checks watcher, triggers if not indexed) | PARTIAL — startup auto-index is implemented via `CBM_AUTO_INDEX`, first-tool-call parity is still deferred |
| Idle store eviction (300s timeout) | Full (`cbm_mcp_server_evict_idle`) | MISSING |
| File URI parsing (`file://` → path) | Full (`cbm_parse_file_uri`) | MISSING |
| Progress notifications | Full (JSON-RPC notification during indexing) | MISSING |

---

## Store (`store.zig` vs `store/store.c`)

The Zig store has the schema (tables + indexes + pragmas) and opens in-memory DBs. All CRUD operations are stubs.

### Project CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_project` | Full | STUB |
| `get_project` | Full | MISSING |
| `list_projects` | Full | MISSING |
| `delete_project` (cascade) | Full | MISSING |

### Node CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_node` (single) | Full (prepared statement) | MISSING |
| `upsert_node_batch` (bulk) | Full | MISSING |
| `find_node_by_id` | Full | MISSING |
| `find_node_by_qn` | Full | MISSING |
| `find_node_by_qn_any` (cross-project) | Full | MISSING |
| `find_nodes_by_name` | Full | MISSING |
| `find_nodes_by_name_any` (cross-project) | Full | MISSING |
| `find_nodes_by_label` | Full | MISSING |
| `find_nodes_by_file` | Full | MISSING |
| `find_nodes_by_file_overlap` (line range) | Full | MISSING |
| `find_nodes_by_qn_suffix` | Full | MISSING |
| `find_node_ids_by_qns` (batch QN→ID) | Full | MISSING |
| `count_nodes` | Full | STUB (returns 0) |
| `delete_nodes_by_project` | Full | MISSING |
| `delete_nodes_by_file` | Full | MISSING |
| `delete_nodes_by_label` | Full | MISSING |

### Edge CRUD

| Operation | C | Zig |
|-----------|---|-----|
| `insert_edge` (single) | Full | MISSING |
| `insert_edge_batch` | Full | MISSING |
| `find_edges_by_source` | Full | MISSING |
| `find_edges_by_target` | Full | MISSING |
| `find_edges_by_source_type` | Full | MISSING |
| `find_edges_by_target_type` | Full | MISSING |
| `find_edges_by_type` | Full | MISSING |
| `find_edges_by_url_path` | Full | MISSING |
| `count_edges` | Full | STUB (returns 0) |
| `count_edges_by_type` | Full | MISSING |
| `delete_edges_by_project` | Full | MISSING |
| `delete_edges_by_type` | Full | MISSING |

### File Hash CRUD (for incremental indexing)

| Operation | C | Zig |
|-----------|---|-----|
| `upsert_file_hash` / `upsert_file_hash_batch` | Full | MISSING |
| `get_file_hashes` | Full | MISSING |
| `delete_file_hash` / `delete_file_hashes` | Full | MISSING |

### Search

| Operation | C | Zig |
|-----------|---|-----|
| `cbm_store_search` (12+ params: label, name_pattern, qn_pattern, file_pattern, relationship, degree, sort, pagination) | Full | MISSING |
| `cbm_glob_to_like` | Full | MISSING |
| `cbm_extract_like_hints` | Full | MISSING |
| `cbm_ensure_case_insensitive` | Full | MISSING |

### Traversal

| Operation | C | Zig |
|-----------|---|-----|
| `cbm_store_bfs` (direction, edge types, max depth, max results) | Full | WORKS (multi-edge-type, max_results) |
| `cbm_hop_to_risk` / `cbm_risk_label` | Full | WORKS |
| `cbm_build_impact_summary` | Full | MISSING |
| `cbm_deduplicate_hops` | Full | MISSING |

### Schema / Architecture

| Operation | C | Zig |
|-----------|---|-----|
| `get_schema` (labels, types, patterns, samples) | Full | MISSING |
| `get_architecture` (languages, packages, entries, routes, hotspots, boundaries, services, layers, clusters, file tree) | Full | MISSING |
| `cbm_louvain` (community detection) | Full | MISSING |
| ADR store/get/delete | Full | WORKS |

### Transaction / Bulk

| Operation | C | Zig |
|-----------|---|-----|
| `begin` / `commit` / `rollback` | Full | MISSING |
| `begin_bulk` / `end_bulk` (pragma tuning) | Full | MISSING |
| `drop_indexes` / `create_indexes` | Full | MISSING |
| `checkpoint` | Full | MISSING |
| `dump_to_file` | Full | MISSING |
| `restore_from` (backup) | Full | MISSING |
| `check_integrity` | Full | MISSING |
| Batch degree counting | Full | MISSING |
| Node degree (in/out) | Full | MISSING |
| Node neighbor names | Full | MISSING |
| List distinct file paths | Full | MISSING |

---

## Graph Buffer (`graph_buffer.zig` vs `graph_buffer/graph_buffer.c`)

| Feature | C | Zig |
|---------|---|-----|
| Upsert node by QN | Full | PARTIAL (works but no properties_json passthrough) |
| Insert edge with dedup | Full (source_id, target_id, type dedup + property merge) | PARTIAL (appends without dedup) |
| Find node by QN | Full | Available via HashMap.get |
| Find node by ID | Full | MISSING |
| Find nodes by label | Full | MISSING |
| Find nodes by name | Full | MISSING |
| Find edges by source+type | Full | MISSING |
| Find edges by target+type | Full | MISSING |
| Find edges by type | Full | MISSING |
| Delete by label (cascade edges) | Full | MISSING |
| Delete by file (cascade edges) | Full | MISSING |
| Shared atomic ID source (for parallel) | Full (`_Atomic int64_t`) | MISSING |
| Merge worker gbufs (QN dedup + edge remap) | Full | MISSING |
| Dump to SQLite | Full (bulk insert path) | MISSING |
| Flush to existing store | Full | MISSING |
| Merge into store (incremental) | Full | MISSING |
| Load from DB | Full | MISSING |
| Foreach node/edge visitors | Full | MISSING |
| Edge dedup on insert | Full (key: source+target+type) | MISSING — current impl just appends |
| Edge count by type | Full | MISSING |
| Delete edges by type | Full | MISSING |

---

## Pipeline (`pipeline.zig` vs `pipeline/pipeline.c` + 20 pass files)

| Feature | C | Zig |
|---------|---|-----|
| Pipeline orchestrator (phase sequencing) | Full (7 phases) | STUB (empty `run()`) |
| File discovery integration | Full | MISSING |
| Graph buffer lifecycle | Full (create → populate → dump) | MISSING |
| Registry lifecycle | Full (build from defs → use in resolution) | MISSING |
| Cancellation (atomic flag) | Full | STUB (field exists, not wired) |
| Memory budget checking | Full | MISSING (deliberately cut per audit) |
| Project name derivation from path | Full (`cbm_project_name_from_path`) | MISSING |
| Pipeline lock (global mutex) | Full | MISSING |

### Pipeline Passes — Historical Initial Audit

| Pass | C LOC | Zig Status | Purpose |
|------|-------|------------|---------|
| `pass_definitions` | ~3,158 (extract_defs.c) | PARTIAL | Tree-sitter → definition nodes for the current target language slice |
| `pass_calls` | 571 | PARTIAL | Call resolution via registry for the current target language slice |
| `pass_usages` | 170 | PARTIAL | Usage/type_ref edges for callback refs and declaration-level type refs in the current target language slice |
| `pass_semantic` | 468 | PARTIAL | Inherits/implements/decorates for the current target language slice |
| `pass_parallel` | 1,427 | MISSING | Thread pool orchestration |
| `pass_similarity` | 505 (minhash.c) | MISSING | MinHash near-clone detection |
| `pass_gitdiff` | ~200 | MISSING | Git diff → changed files/hunks |
| `pass_route_nodes` | 742 | WORKS for graph-model parity fixture contract (stub and concrete URL/path/topic Route nodes, verified decorator-backed `Route`/`HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared `ASYNC_CALLS`, and route summary exposure) | HTTP/async route node creation, first handler association slice, and first data-flow bridge |
| `pass_tests` | 285 | WORKS for the shared Python `TESTS` / `TESTS_FILE` slice | Test file/function tagging now verified on the local parity fixture; broader language breadth stays follow-on work |
| `pass_enrichment` | ~200 | MISSING (deferred) | Decorator tag enrichment |
| `pass_configlink` | ~200 | WORKS for graph-model parity fixture contract (Strategy 1 key-symbol + Strategy 2 dependency-import; strict shared key-symbol fixture and Zig dependency-import deduplication coverage are locked) | Config-code linking |
| `pass_githistory` | 514 | WORKS | Change coupling from git log |
| `pipeline_incremental` | ~400 | MISSING (deferred) | Incremental re-indexing |

### Extraction Layer (internal/cbm/)

| Component | C LOC | Zig Status |
|-----------|-------|------------|
| `extract_defs.c` (definition extraction) | 3,158 | PARTIAL |
| `extract_calls.c` (call site extraction) | 635 | PARTIAL |
| `extract_imports.c` (import extraction) | 872 | PARTIAL |
| `extract_usages.c` (usage extraction) | 170 | PARTIAL |
| `extract_semantic.c` (inherits/decorates) | 234 | PARTIAL |
| `extract_unified.c` (single-pass dispatcher) | 744 | PARTIAL |
| `extract_type_refs.c` | 361 | MISSING |
| `extract_type_assigns.c` | 197 | MISSING |
| `extract_env_accesses.c` | 215 | MISSING |
| `lang_specs.c` (per-language AST patterns) | 1,199 | MISSING |
| `cbm.c` (extraction entry point) | 452 | MISSING |
| `helpers.c` (AST traversal utilities) | 914 | MISSING |
| `service_patterns.c` (HTTP framework patterns) | 512 | MISSING |
| `ac.c` (Aho-Corasick, cut per audit) | 428 | N/A — cut |

### Tree-sitter Grammars

| Item | C | Zig |
|------|---|-----|
| 66 grammar .c files compiled into binary | Full | MISSING — build.zig pattern exists but no grammar files copied |
| Grammar → Language mapping | Full (lang_specs) | MISSING |
| Tree-sitter parser creation per language | Full | MISSING |

### LSP Integration (deferred)

| Component | C | Zig |
|-----------|---|-----|
| C LSP (include resolution, type inference) | Full (~1,000 LOC) | MISSING (deferred) |
| Go LSP (interface satisfaction, method sets) | Full (~1,000 LOC) | MISSING (deferred) |
| Type registry (symbol → type mapping) | Full | MISSING (deferred) |
| Scope analysis | Full | MISSING (deferred) |

---

## Cypher Engine (`cypher.zig` vs `cypher/cypher.c`)

| Component | C | Zig |
|-----------|---|-----|
| Lexer (50+ token types) | Full (3,412 LOC total) | PARTIAL — enum exists, no lexer logic |
| Parser (AST: patterns, WHERE, RETURN, ORDER BY, LIMIT) | Full | MISSING |
| Node/relationship pattern parsing | Full (labels, properties, variable-length paths) | MISSING |
| WHERE clause parsing (AND/OR/NOT/XOR, =, <>, =~, CONTAINS, STARTS/ENDS WITH, IN, IS NULL) | Full | MISSING |
| RETURN clause (items, aliases, aggregates, DISTINCT, ORDER BY, LIMIT, SKIP) | Full | MISSING |
| CASE expressions | Full | MISSING |
| UNION / UNWIND | Full | MISSING |
| WITH clause | Partial | MISSING |
| OPTIONAL MATCH | Not supported | N/A |
| Executor (AST → SQL → results) | Full | MISSING |
| Write operations (CREATE/DELETE/SET) | Rejected with error | MISSING |
| Max rows enforcement | Full (100k ceiling) | MISSING |

---

## Discover (`discover.zig` vs `discover/discover.c` + `language.c` + `gitignore.c`)

| Feature | C | Zig |
|---------|---|-----|
| Language detection by extension | Full (534 LOC) | PARTIAL — `StaticStringMap` with ~70 extensions |
| Language detection by filename (Makefile, CMakeLists.txt, Dockerfile, etc.) | Full | MISSING |
| .m file disambiguation (ObjC vs Magma vs MATLAB) | Full (reads first 4KB) | MISSING |
| Directory walk (recursive) | Full | STUB (returns empty) |
| Hardcoded skip dirs (.git, node_modules, build, etc.) | Full | MISSING |
| Hardcoded skip suffixes (.pyc, .png, .o, etc.) | Full | MISSING |
| Fast-mode skip patterns (.d.ts, .pb.go, etc.) | Full | MISSING |
| Fast-mode skip filenames (LICENSE, go.sum, etc.) | Full | MISSING |
| .gitignore loading and matching | Full (fnmatch semantics) | MISSING |
| .cbmignore support | Full | MISSING |
| Symlink skipping | Full | MISSING |
| User config (custom extension mappings) | Full (`userconfig.c`) | MISSING |
| Max file size filter | Supported | MISSING |

---

## Watcher (`watcher.zig` vs `watcher/watcher.c`)

| Feature | C | Zig |
|---------|---|-----|
| Watch/unwatch projects | Full | WORKS |
| Git HEAD polling (`git rev-parse HEAD`) | Full | WORKS |
| Dirty tree check (`git status --porcelain`) | Full | WORKS |
| Adaptive poll interval | Full | WORKS |
| Blocking poll loop with sleep | Full | WORKS |
| Index callback invocation | Full | WORKS |
| Stop signal (atomic) | Full | WORKS |
| Per-project state (last_head, last_dirty) | Full | WORKS (tracks HEAD + baseline metadata) |
| Thread-safe stop | Full | WORKS |

---

## Registry (`registry.zig` vs `pipeline/registry.c`)

| Feature | C | Zig |
|---------|---|-----|
| Add symbol (name, QN, label) | Full | PARTIAL (works but no string ownership) |
| Resolve by name | Full (5-strategy chain) | PARTIAL (first-match only, no strategies) |
| Import map integration | Full | MISSING |
| Same-module resolution | Full | MISSING |
| Same-package resolution | Full | MISSING |
| Import-reachable prefix check | Full | MISSING |
| Fuzzy resolve (bare name) | Full | MISSING |
| Exists check | Full | Works |
| Size | Full | Works |
| Find by name (all candidates) | Full | MISSING |
| Find by suffix | Full | MISSING |
| Label lookup | Full | MISSING |
| Confidence banding | Full | MISSING |

---

## CLI (`main.zig` vs `cli/cli.c`)

| Feature | C LOC | Zig Status |
|---------|-------|------------|
| `--version` | Full | Works |
| `--help` | Full | Works |
| `install` (10 agent auto-detection, config writing, hook setup) | ~1,200 | STUB (prints "not yet implemented") |
| `uninstall` (config removal, hook cleanup) | ~400 | STUB |
| `update` (version check, binary download, self-replace) | ~600 | STUB |
| `config list/get/set/reset` | ~300 | STUB |
| `cli <tool> <json>` (single tool invocation) | ~100 | STUB |
| `--progress` flag for CLI mode | Full | MISSING |
| Agent detection (Claude Code, Codex, Gemini, Zed, OpenCode, Antigravity, Aider, KiloCode, VS Code, OpenClaw) | Full | MISSING |
| Config persistence (`~/.cache/codebase-memory-mcp/config.json`) | Full | MISSING |
| Progress sink (stderr JSON lines) | Full | MISSING |

---

## MinHash (`minhash.zig` vs `simhash/minhash.c`)

| Feature | C | Zig |
|---------|---|-----|
| Fingerprint struct (K=64 u32 values) | Full | Works |
| Jaccard similarity | Full | Works |
| Hex encode/decode | Full | PARTIAL (encode only) |
| `cbm_minhash_compute` (AST → trigrams → signature) | Full | MISSING — needs tree-sitter integration |
| LSH index (insert, query candidates) | Full | MISSING |
| LSH parameters (32 bands x 2 rows) | Full | MISSING |
| Min-node gate (30 leaf tokens) | Full | Constant defined, not enforced |
| Same-file/same-language filtering | Full | MISSING |
| Max edges per node cap (10) | Full | MISSING |

---

## Foundation Layer (Zig stdlib replaces most, but gaps remain)

| C Component | Zig Replacement | Status |
|-------------|----------------|--------|
| `arena.c` | `std.heap.ArenaAllocator` | Available (not yet used in any module) |
| `hash_table.c` | `std.StringHashMap` / `std.AutoHashMap` | Used |
| `dyn_array.h` | `std.ArrayList` | Used |
| `str_intern.c` | `StringHashMap(void)` on arena | Not yet built |
| `str_util.c` (starts_with, ends_with, trim, etc.) | `std.mem` builtins | Available |
| `log.c` (structured JSON logging) | `std.log` | Not yet configured |
| `platform.c` (mmap, timers, CPU count, home dir) | `std.os` / `std.posix` / `std.fs` | Not yet used |
| `diagnostics.c` (perf metrics to JSON) | Nothing yet | MISSING |
| `compat_thread.c` | `std.Thread` | Not yet used |
| `compat_fs.c` (path normalization) | `std.fs.path` | Available |
| `constants.h` (buffer sizes) | Zig comptime constants | MISSING |
| `system_info.c` (RAM size, CPU count) | `std.os` | Not yet used |
| FQN computation (`fqn.c`) | Not yet built | MISSING |

---

## Summary by Priority

### P0 — Required for "can index a repo and answer queries"

- Store CRUD (nodes, edges, projects) with prepared statements
- Graph buffer → SQLite dump path
- File discovery (directory walk, gitignore, language detection)
- Tree-sitter extraction (definitions at minimum)
- Pipeline orchestrator (at least single-threaded: discover → extract → dump)
- Registry (add + basic resolve)
- MCP protocol layer (JSON-RPC parsing, initialize, tools/list)
- At least `index_repository`, `search_graph`, `query_graph`, `list_projects` tool handlers
- Cypher engine (or simplified SQL translator per audit recommendation)

### P1 — Required for feature parity with daily use

- Remaining 9 MCP tool handlers
- Call resolution (full 5-strategy chain)
- Usage/semantic/test passes
- Parallel extraction (thread pool + worker buffers)
- Watcher (git polling + auto-reindex)
- Incremental indexing
- CLI install/uninstall (agent detection)
- MinHash computation + LSH index

### P2 — Polish and deferred features

- Git history pass (change coupling)
- Route node creation
- Config-code linking
- Decorator enrichment
- CLI update (self-update)
- Diagnostics/structured logging
- Impact analysis edge-type weighting (per audit #36)

### Line count estimate

| Category | Estimated Zig LOC to write |
|----------|---------------------------|
| P0 (minimum viable) | ~8,000-10,000 |
| P1 (feature parity) | ~6,000-8,000 |
| P2 (polish) | ~3,000-4,000 |
| **Total** | **~17,000-22,000** |

Current Zig LOC (stubs): ~1,200
