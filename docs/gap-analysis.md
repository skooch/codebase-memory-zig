# Gap Analysis: Zig Port vs C Original

Historical subsystem gap register for the Zig port versus the original C implementation.

This document no longer represents an "everything still missing" list. Most of the previously important shared-surface gaps are now closed. Use it as a detailed backlog and planning reference, not as the first-stop summary of current project status.

Status key: **WORKS** (implemented for the current target contract), **STUB** (type signatures exist, no implementation), **MISSING** (not present at all), **PARTIAL** (some logic, incomplete)

For the most readable current-state comparison against the original implementation, see:
- [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md)

For the repo-facing summary and setup story, see:
- [README.md](/Users/skooch/projects/codebase-memory-zig/README.md)

The detailed subsystem tables below are historical backlog references. When a table entry disagrees with the current snapshot, treat the current snapshot and [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md) as authoritative, and update the table during the next focused phase for that subsystem.

## Current Snapshot

Baseline note:
- Treat the latest upstream release, `codebase-memory-mcp` `v0.6.0` from `2026-04-06`, as the C-side comparison baseline for current port-state claims.
- The older "target contract complete" language in this repo still applies to the pre-`v0.6.0` execution plan, but it no longer implies latest-upstream parity.

Verification posture today:
- The pre-`v0.6.0` target contract is complete; the remaining backlog is now a mix of latest-upstream parity work, deliberate scope exclusions, and historical subsystem notes.
- The repo has broad automated coverage across `zig build test`, zig-only interop goldens, zig-only CLI parity goldens, and CI-run benchmark, soak, and static security checks.
- CI now also runs the full Zig-vs-C interop and CLI parity comparison against the reference implementation on pull requests and pushes to `main` when interop-relevant files change, while retaining a weekly scheduled sweep.
- That coverage is broad enough to support the current daily-use contract claims, but it is **not** exhaustive of every feature and edge case.
- Treat [port-comparison.md](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md) as the authoritative statement of what the repo can truthfully claim today.

Newest latest-upstream deltas reopened by `v0.6.0`:
- `search_graph` in the original now has BM25 `query` search and vector-backed `semantic_query`; Zig still only exposes the structured graph-search path.
- `index_repository` in the original now supports `full`, `moderate`, and `fast`; Zig still exposes only `full` and `fast`.
- The original now emits `SEMANTICALLY_RELATED` and channel `LISTENS_ON` edges; Zig still lacks those exact graph contracts, even where bounded route/topic behavior overlaps.
- Protocol/tool-surface exactness also now requires the visible `ingest_traces`
  stub and upstream-style `repo_path` naming, but those are surface-plumbing
  tasks rather than substantive graph-model gaps.

Known coverage gaps in the current automated suite:
- Current local audit on `2026-04-21`: `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, `bash scripts/run_cli_parity.sh --zig-only`, and the current ops suite entrypoints all pass. The current `bash scripts/run_interop_alignment.sh` baseline now reports `39` fixtures, `301` comparisons, `164` strict matches, `45` diagnostic-only comparisons, and `0` mismatches, with `protocol-contract`, the query-analysis exact fixtures, and the new graph-exactness fixture set scoring as strict shared matches while `tool-surface-parity` remains diagnostic-only because Zig still lacks a real `moderate` indexing mode.
- `detect_changes.since` is no longer part of the latest-upstream gap list: Zig now exposes the released selector surface with direct unit coverage for commit-ish refs, ISO-date selectors, and invalid-selector errors, even though the stale local C comparator still only exercises `base_branch`.
- Merge-blocking CI now includes the full Zig-vs-C compare for interop-touching pull requests and pushes to `main`, while non-interop changes still rely on zig-only goldens plus unit and integration tests.
- Packaging and setup entrypoints are exercised by verification runs and workflows, and the release workflow now merges and validates a repo-owned `release-manifest.json`, but the repo still does not have exhaustive cross-platform regression automation for every shell, host, or archive flow.
- Windows coverage is strong at config-path, installer-layout, no-`HOME` env fallback, runtime DB root creation, and PowerShell entrypoint level, but not exhaustive of native runtime and filesystem edge cases.
- Framework-specific route registration, broker-specific event semantics, and richer Cypher permutations are covered by bounded fixtures rather than exhaustive matrix testing.
- Error-path and state-transition coverage exists in unit tests for several subsystems, but not as a comprehensive end-to-end parity matrix across every MCP tool and CLI surface.

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
- Parser-backed definition extraction is working for the readiness languages
  plus the first follow-on expansion tranche:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
  - Go
  - Java
  - C#
  - PowerShell
  - GDScript
- The first-gate fixture harness baseline is:
  - `Strict matches: 58`
  - `Diagnostic-only comparisons: 9`
  - `Mismatches: 0`
- The expanded full harness currently reports:
  - `Fixtures: 39`
  - `Comparisons: 301`
  - `Strict matches: 164`
  - `Diagnostic-only comparisons: 45`
  - `Known mismatches: 0`
  - `cli_progress: match`
  - `protocol-contract`: strict shared match
  - `snippet-trace-contract`: strict shared match
  - `search-code-ranking-parity`: strict shared match
  - `history-similarity-parity`: strict shared match
  - `tool-surface-parity`: diagnostic-only by design because latest-upstream `moderate` mode is still missing in Zig
  - no remaining snippet, trace, search, JavaScript-ordering, Java query-shape, or error-path comparison mismatches
  - the former Go method-ownership delta is now diagnostic-only instead of a hard mismatch

Completed after the readiness gate:
- Runtime lifecycle and scale baseline:
  - watcher-driven auto-index and auto-reindex
  - startup watcher registration for previously indexed projects
  - incremental indexing
  - parallel extraction and graph-buffer merge
  - MinHash/LSH similarity edges
  - signal-driven graceful shutdown for stdio MCP sessions
  - one-shot startup update notification on the first post-initialize response
  - timed idle runtime-store eviction plus reopen on the next stdio tool call
  - direct startup tests for persisted watcher registration and startup
    auto-index of the current repo
- CLI and productization baseline:
  - persisted runtime config
  - `install`, `uninstall`, `update`, and `config`
  - `cli --progress`
  - installer support for Codex CLI and Claude Code
- Operational script baseline:
  - Zig-only benchmark wrapper suitable for CI or local worktrees
  - reproducible soak suite for repeated index and query cycles
  - repo-owned static security audit suite
  - maintainer operations docs and CI workflow wiring
- Parser-backed language-expansion tranche:
  - Go functions, methods, structs, and interfaces
  - Java classes, interfaces, constructors, and methods
  - scoped zig-only interop goldens for `go-basic`, `go-parity`, and
    `java-basic`
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
- Semantic graph first tranche:
  - explicit `src/routes.zig` route helpers now own route identity and creation
  - explicit `src/semantic_links.zig` now synthesizes `EventTopic` nodes plus
    `EMITS` and `SUBSCRIBES` edges from async route facts
  - `get_architecture` now supports `message_summaries`
  - `trace_call_path(mode="cross_service")` now traverses `EMITS` and
    `SUBSCRIBES` in addition to HTTP, async, and data-flow edges
  - current evidence: `zig build`, `zig build test`, and direct fixture-level
    CLI verification on `testdata/interop/semantic-expansion/http_routes` and
    `testdata/interop/semantic-expansion/pubsub_events`

Intentionally deferred after Phase 7:
- The remaining MCP work outside the completed daily-use slice, especially fuller Cypher parity.
- Full Cypher parity beyond the broader day-to-day query subset now supporting node and edge reads, filtering, sorting, counts, distinct selection, boolean-precedence predicates, numeric property predicates, and edge-type filtering.
- Deeper usage/type-reference extraction parity and broader cross-language semantics beyond the current target daily-use slice.
- Higher-order graph analytics and broader framework expansion beyond the now-implemented route, event-topic, and config-link fixture slices. (Git-history coupling is implemented; route nodes, event-topic links, and config-linking all have verified bounded slices.)
- Broader installer/self-update behavior beyond the current source-build-friendly Codex CLI / Claude Code support.

Completed in Plan 03:
- Advanced trace parity: modes (calls/data_flow/cross_service), multi-edge-type BFS, risk labels, test-file filtering, function_name alias, structured callees/callers response format.

Completed in Plan 05:
- Long-tail edge parity: `THROWS`/`RAISES` edges from throw statements (JS/TS/TSX). Verified end-to-end on the edge-parity fixture with RAISES resolving custom error classes. The public harness now also proves bounded shared zero-row `WRITES` / `READS` results across the exercised Python, JavaScript, TypeScript, and local-state micro-cases. Out-of-scope or still-unproven positive overlaps: `OVERRIDE` (Go-only), `CONTAINS_PACKAGE` (never implemented in C), and broader positive `WRITES` / `READS` extraction.

## Implemented Plan: Language Coverage Expansion

Current parser-backed expansion tranche:
- Go
  - functions
  - methods with receiver ownership
  - struct definitions
  - interface definitions
  - import parsing
- Java
  - classes
  - interfaces
  - constructors
  - methods
  - import parsing
- fixture surface
  - upgraded `go-basic`
  - upgraded `go-parity`
  - new `java-basic`

Completion evidence:
- the plan is now archived at
  [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/07-language-coverage-expansion-plan.md)
  and
  [07-language-coverage-expansion-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/07-language-coverage-expansion-progress.md)
- `build.zig` now compiles vendored Go and Java parsers, and
  `scripts/fetch_grammars.sh` now fetches those grammar sources for fresh
  clones
- `src/extractor.zig` now uses tree-sitter for Go and Java definitions,
  including Go receiver ownership and Java constructor or method ownership
- the interop manifest now has a Java fixture under
  `testdata/interop/language-expansion/java-basic`, and the Go goldens now
  capture non-empty graph facts instead of empty diagnostic snapshots

Completion verification on 2026-04-19:
- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
- `zig build`
- `zig build test`
- scoped zig-only interop subset for `go-basic`, `go-parity`, and `java-basic`
- scoped Zig-vs-C interop subset for `go-basic`, `go-parity`, and `java-basic`

Observed results:
- scoped zig-only goldens:
  - `go-basic`: pass
  - `go-parity`: pass
  - `java-basic`: pass
- scoped Zig-vs-C compare:
  - `go-basic`: pass
  - `go-parity`: pass
  - `java-basic`: pass

Intentional residual delta after completion:
- bounded Go hybrid-resolution sidecars are now implemented for both the original single-call case and an expanded multi-document sidecar slice, but C/C++ hybrid resolution remains deferred
- C++, R, Svelte, and Vue parser-backed expansion remain deferred
- the exercised shared Go and Java fixture rows now full-compare cleanly, so
  both languages can be promoted from verified Zig-side expansion to strict
  shared parity for the bounded fixture contract this repo actually asserts

## Implemented Plan: Language Support Expansion Feature Cluster

Current parser-backed tranche:
- PowerShell
  - top-level functions
  - classes
  - class methods with owner linkage
- GDScript
  - top-level `class_name`
  - nested classes
  - top-level functions
  - class-owned methods

Queue decision for this completed slice:
- chosen first tranche
  - PowerShell
  - GDScript
- explicit deferred next candidate
  - QML

Scored queue captured during selection:
- PowerShell
  - demand: high
  - parser availability: high
  - overlap with current Zig goals: high
  - verification cost: low
- GDScript
  - demand: medium
  - parser availability: high
  - overlap with current Zig goals: medium
  - verification cost: low
- QML
  - demand: medium
  - parser availability: medium
  - overlap with current Zig goals: medium
  - verification cost: medium-high

Completion evidence:
- the plan is now archived at
  [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/language-support-expansion-feature-cluster-plan.md)
  and
  [language-support-expansion-feature-cluster-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/language-support-expansion-feature-cluster-progress.md)
- `build.zig` now compiles vendored PowerShell and GDScript parsers
- `scripts/fetch_grammars.sh` now fetches pinned PowerShell and GDScript
  grammar sources in a Bash 3.2-compatible way
- `src/discover.zig` now recognizes `.ps1`, `.psm1`, `.psd1`, and `.gd`
- `src/extractor.zig` now uses tree-sitter for PowerShell and GDScript
  definition extraction
- [`docs/language-support.md`](/Users/skooch/projects/codebase-memory-zig/docs/language-support.md)
  now separates extension detection, parser-backed extraction, and semantic
  parity claims

Completion verification on 2026-04-19:
- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
- `bash scripts/fetch_grammars.sh --force`
- `zig build`
- `zig build test`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/powershell-basic"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli query_graph '{"project":"powershell-basic","query":"MATCH (n) WHERE n.file_path = \"main.ps1\" RETURN n.label, n.name ORDER BY n.label, n.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/gdscript-basic"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli query_graph '{"project":"gdscript-basic","query":"MATCH (n) WHERE n.file_path = \"main.gd\" RETURN n.label, n.name ORDER BY n.label, n.name"}'`

Observed results:
- PowerShell fixture returned `Class Worker`, `Function Invoke-Users`, and
  `Method Run`
- GDScript fixture returned `Class Hero`, `Class Worker`, `Function boot`, and
  `Method run`

Intentional residual delta after completion:
- QML remains the next candidate lane and is not extension-recognized or
  parser-backed in this branch
- PowerShell and GDScript are verified parser-backed additions, not yet a
  broader semantic-parity claim against the original C implementation

## Implemented Plan: Language Breadth Expansion

Current parser-backed tranche for this completed slice:
- C#
  - interfaces
  - classes
  - constructors
  - class-owned methods

Queue decision for this completed slice:
- chosen tranche
  - C#
- explicit deferred next candidates
  - QML
  - any broader two-language tranche after the current single-language proof

Completion evidence:
- the plan is now archived at
  [11-language-breadth-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/11-language-breadth-expansion-plan.md)
  and
  [11-language-breadth-expansion-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/11-language-breadth-expansion-progress.md)
- `build.zig` now compiles the vendored C# parser
- `scripts/fetch_grammars.sh` now fetches the pinned C# grammar alongside the
  existing parser-backed tranche
- `src/extractor.zig` now uses tree-sitter for bounded C# definition
  extraction, including constructor and method ownership
- `src/store_test.zig` now locks the C# fixture into the store-backed parser
  regression coverage
- [`docs/language-support.md`](/Users/skooch/projects/codebase-memory-zig/docs/language-support.md)
  and [`docs/port-comparison.md`](/Users/skooch/projects/codebase-memory-zig/docs/port-comparison.md)
  now classify C# correctly as a Zig-only parser-backed expansion rather than a
  shared semantic-parity claim

Completion verification on 2026-04-20:
- `bash scripts/fetch_grammars.sh --force`
- `zig build`
- `zig build test`
- `zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/csharp-basic"}'`
- `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Class"}'`
- `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Interface"}'`
- `zig build run -- cli search_graph '{"project":"csharp-basic","label":"Method"}'`
- `zig build run -- cli query_graph '{"project":"csharp-basic","query":"MATCH (a)-[:DEFINES_METHOD]->(b:Method) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'`

Observed results:
- the C# fixture indexed to `11` nodes and `17` edges
- `search_graph` returned `Class Entry`, `Class Worker`, and `Interface IRunner`
- `search_graph` returned the method inventory `Boot`, `Helper`, `Run`,
  `Run`, and `Worker`
- `query_graph` returned `DEFINES_METHOD` rows for `Entry -> Boot`,
  `IRunner -> Run`, `Worker -> Helper`, `Worker -> Run`, and
  `Worker -> Worker`

Intentional residual delta after completion:
- C# is a bounded Zig-only parser-backed addition, not yet a shared parity
  claim against the original C implementation
- QML remains deferred because its first useful contract is still tied to the
  richer object and property model rather than a cheap declaration-only slice

## Implemented Plan: Operational Controls and Configurability

Current control-surface inventory from the Zig implementation:

- persisted config keys
  - `auto_index`
  - `auto_index_limit`
  - `idle_store_timeout_ms`
  - `update_check_disable`
  - `install_scope`
  - `install_extras`
  - `download_url`
- path and config-root overrides
  - `CBM_CONFIG_PLATFORM`
  - `CBM_CACHE_DIR`
  - `CBM_EXTENSION_MAP`
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
  - explicit side-effect control: `--mcp-only`

Completion evidence for this plan:

- the plan is now archived at
  [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/operational-controls-and-configurability-feature-cluster-plan.md)
  and
  [operational-controls-and-configurability-feature-cluster-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/operational-controls-and-configurability-feature-cluster-progress.md)
- the current branch proves persisted `config set|get|list|reset` handling for:
  - `idle_store_timeout_ms`
  - `update_check_disable`
  - `install_scope`
  - `install_extras`
- the CLI now makes installer scope and side effects explicit:
  - default CLI scope is `shipped`
  - `--scope detected` is the explicit broader detected-agent path
  - default CLI mode manages MCP entries plus extras
  - `--mcp-only` keeps MCP entry changes while skipping instructions, skills,
    and hooks
- extension remapping is now explicit and verified through env-only
  `CBM_EXTENSION_MAP`, with the temp-home parity lane proving `.foo=python`
  indexing and `search_graph` lookup
- the fixture-backed configuration lane now lives under
  `testdata/interop/configuration/` and `scripts/run_cli_parity.sh`, so these
  controls no longer depend on a developer home directory

Intentional omissions after completion:

- host bind/listen controls remain absent because the shipped server mode is
  stdio-only
- the shipped default installer scope remains intentionally narrower than the
  broader detected-scope ecosystem, even though the detected-scope matrix is
  now verified
- extension remapping is explicit and verified, but remains env-only rather
  than a richer persisted policy layer

## Implemented Plan: Installer Ecosystem Parity

Current matrix for the completed slice:
- broader detected-scope installer targets under fixture-backed verification
  - Codex CLI
  - Claude Code
  - Gemini
  - Zed
  - OpenCode
  - Antigravity
  - Aider
  - KiloCode
  - VS Code
  - OpenClaw
- broader auxiliary side effects now verified in temp-home lanes
  - Claude hooks, reminder script, and consolidated skill package
  - Codex `AGENTS.md`
  - Gemini `BeforeTool` hook and `GEMINI.md`
  - OpenCode `AGENTS.md`
  - Antigravity `AGENTS.md`
  - Aider `CONVENTIONS.md`
  - KiloCode rules file
- command behavior under proof
  - detected-scope `install`
  - detected-scope `update --dry-run`
  - detected-scope `uninstall`
  - shared Codex/Claude compare still green against the original C binary

Completion evidence:
- `src.main.printInstallReport` now reports the broader detected-agent matrix
  instead of only the shared shipped pair, and `install` / `update` no longer
  falsely reject a detected-scope run that finds only non-shipped targets.
- `scripts/run_cli_parity.sh` now seeds `testdata/cli-agent-fixtures/` and
  verifies the broader ten-agent temp-home matrix, including config merges,
  broader instruction/hook/rules side effects, uninstall cleanup, and
  detected-scope update reporting.
- `docs/installer-matrix.md` now reflects the verified broader client and
  auxiliary-file roots instead of only the earlier shared or Windows-writer
  subset.

Intentional residual delta after completion:
- the shipped default scope remains `shipped`, even though the broader
  detected-scope matrix is now verified
- the verified self-update contract is intentionally bounded to configured
  file-backed packaged archives on supported Unix and macOS hosts rather than
  the original's broader network-backed updater flow
- Claude skill packaging remains consolidated into one `codebase-memory` skill
  rather than the original multi-skill layout

## Implemented Plan: Operations Script Suite

Current operations surface for the completed slice:
- benchmark entrypoint
  - `scripts/run_benchmark_suite.sh`
  - `scripts/run_benchmark_suite.py`
  - `--zig-only`, `--manifest`, and `--report-dir` support for CI-safe runs
- soak entrypoint
  - `scripts/run_soak_suite.sh`
  - generated local git repo with repeated index, `search_graph`, and
    `get_architecture` cycles
  - machine-readable reports under `.soak_reports/`
- static audit entrypoint
  - `scripts/run_security_audit.sh`
  - portable shell, URL, installer-pattern, and destructive-command checks
  - machine-readable reports under `.security_reports/`
- maintainer and CI wiring
  - `docs/operations.md`
  - `.github/workflows/ops-checks.yml`

Completion evidence:
- the plan is now archived at
  [09-operations-script-suite-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/09-operations-script-suite-plan.md)
  and
  [09-operations-script-suite-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/09-operations-script-suite-progress.md)
- `scripts/run_benchmark_suite.sh` now runs in `--zig-only` mode without
  requiring the sibling C binary, which makes the existing benchmark harness
  safe for CI and peer worktrees
- `scripts/run_soak_suite.sh` now generates a local temporary repo, mutates it
  across iterations, and proves repeated Zig-only index and query cycles
- `scripts/run_security_audit.sh` now gives this repo a portable static audit
  layer for shell entrypoints, runtime URLs, download-and-exec patterns, and
  destructive command guards
- `.github/workflows/ops-checks.yml` now exercises benchmark, soak, and static
  audit entrypoints on GitHub Actions, and `docs/operations.md` documents the
  supported maintainer flow

Completion verification on 2026-04-19:
- `bash -n scripts/run_benchmark_suite.sh scripts/run_soak_suite.sh scripts/run_security_audit.sh`
- `python3 -m py_compile scripts/run_benchmark_suite.py`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ops-checks.yml"); puts "ok"'`
- `zig build`
- `zig build test`
- `bash scripts/run_benchmark_suite.sh --zig-only --manifest testdata/bench/stress-manifest.json --report-dir .benchmark_reports/ops`
- `bash scripts/run_soak_suite.sh --iterations 4 --report-dir .soak_reports/ops`
- `bash scripts/run_security_audit.sh .security_reports/ops`

Observed results:
- benchmark medians
  - `self-repo`: `1340.308 ms`
  - `sqlite-amalgamation`: `72.769 ms`
- soak report
  - index median: `55.428 ms`
  - index p95: `303.966 ms`
  - `search_graph` median: `11.075 ms`
  - `get_architecture` median: `11.684 ms`
- security audit report
  - check count: `17`
  - failure count: `0`

Intentional residual delta after completion:
- no binary-string audit layer equivalent to the original's post-build script
- no runtime network-trace audit layer
- no fuzz harnesses in the Zig repo today
- no nightly or multi-hour soak tier beyond the reproducible local suite

Current classification note after the runtime/CLI/packaging parity review:
- keep the local benchmark, soak, and static audit suite as implemented
  operational coverage, but do not describe it as full parity with the latest
  upstream audit surface
- keep the standard-binary release, install, and setup path as implemented and
  verified, but do not describe it as packaging parity with the latest upstream
  UI, signing, provenance, or broader release-metadata surface

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
- `src.cli.homeDir` and the runtime-cache helpers now also handle Windows
  sessions where `HOME` is unset but `USERPROFILE` or `HOMEDRIVE` plus
  `HOMEPATH` are present, which removes a real Windows-native runtime and
  installer path-resolution gap.
- `src.cli.detectAgents` and the Zed, VS Code, and KiloCode install helpers now
  route through shared config-platform path helpers instead of deriving paths
  only from the host OS tag, which makes Windows-layout checks reproducible on
  a non-Windows host.
- `scripts/run_cli_parity.sh --zig-only` now seeds fixture-backed Windows
  layouts under `APPDATA` / `LOCALAPPDATA`, drops `HOME`, and verifies the Zig
  installer plus runtime-config paths there through `USERPROFILE`.
- `src.mcp.handleLine` now ignores no-`id` notifications, and the runtime
  harness proves `notifications/initialized` stays silent while the first real
  tool response still receives the one-shot update notice.
- `scripts/test_runtime_lifecycle.sh` now also proves a Windows env-fallback
  stdio session creates the runtime DB under `LOCALAPPDATA` and still carries
  the one-shot startup notice while `HOME` is unset.

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

## Implemented Plan: Release And Setup Packaging

Completed packaging surface in the Zig repo:

- release artifacts published as versioned archives instead of only local
  `zig build` output
- top-level install entrypoints:
  - `install.sh`
  - `install.ps1`
- setup/bootstrap entrypoints:
  - `scripts/setup.sh`
  - `scripts/setup-windows.ps1`
- release automation:
  - `.github/workflows/release.yml`
- end-user install documentation describing archives, checksums, and setup flow

Completion evidence for this plan:

- the plan is now archived at
  [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/release-and-setup-packaging-plan.md)
  and
  [release-and-setup-packaging-progress.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/release-and-setup-packaging-progress.md)
- `build.zig` now exposes `zig build release` for a ReleaseSafe installable
  binary target
- `scripts/package-release.sh` now produces release-style archives plus
  `checksums.txt` and `release-manifest.json`, including a verified Windows zip
  artifact
- `install.sh`, `install.ps1`, `scripts/setup.sh`, and
  `scripts/setup-windows.ps1` now verify and install the packaged binary from a
  release directory or build it from source
- `.github/workflows/release.yml` now assembles those artifacts into a draft
  GitHub release and validates the merged manifest against the final release
  archive set
- `docs/install.md` now documents the standard-binary release/install contract
- `docs/release-hardening.md` now documents the repo-owned manifest contract and
  the deliberate exclusion of signing and external attestation

Intentional omissions after completion:

- no UI variant packaging
- no signing, SBOM, provenance, or VirusTotal stages in this slice
- packaging remains separate from broader agent-ecosystem expansion, which is
  still owned by the installer backlog
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
| `CONFIGURES` / `USES_TYPE` | `CONFIGURES` and `USES_TYPE` are at shared-fixture parity; `WRITES` / `READS` now have bounded shared zero-row coverage across the exercised Python, JavaScript, TypeScript, and local-state micro-cases, but broader positive overlap is still unproven | The Zig graph emits the same overlapping edge families, target resolution, and retained metadata as the original on parity fixtures that exercise config files and type references | `src/extractor.zig`, `src/pipeline.zig`, `src/graph_buffer.zig`, `src/store.zig` | Parity fixtures plus interop graph/query comparisons |
| `THROWS` / `RAISES` | Zig now extracts throw/raise edges for JS/TS/TSX | The Zig graph emits `THROWS` and `RAISES` edges from throw statements with the same checked/unchecked classification heuristic as the original | `src/extractor.zig`, `src/pipeline.zig` | Edge-parity fixture plus store tests |
| `install`, `uninstall`, `update` | Zig now proves the broader detected-scope matrix plus a bounded file-backed self-update path | The Zig CLI verifies broader detected-scope config persistence, reporting, reversible filesystem changes, and packaged-archive self-replacement in temp-HOME tests while keeping the shared Codex/Claude compare green against the original | `src/cli.zig`, `src/main.zig` | Temp-HOME command parity checks, expanded zig-only installer matrix lane, and shared Zig/C command comparison |
| Auto-detected agent integrations | Zig now detects and reports the broader 10-agent matrix it claims to support, while the shipped default scope stays narrower | The Zig CLI auto-detects every current supported target in the same environments its temp-home harness creates and reports the same broader matrix shape the original documents | `src/cli.zig`, `src/main.zig` | Temp-HOME detection matrix tests plus CLI output comparison |

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
- Language expansion beyond the implemented first tranche:
  - hybrid type/LSP resolution beyond the implemented Go sidecar slice,
    including C/C++ and any live external resolver integrations
  - broader parser-backed families beyond Go and Java
- Metadata and enrichment:
  - git-history coupling — now implemented (subprocess `git log`, `FILE_CHANGES_WITH` edges)
  - long-tail edges — now implemented: `THROWS`/`RAISES` (JS/TS/TSX throw statements), decorator-backed `HANDLES`, route-linked `DATA_FLOWS`, and bounded shared zero-row `WRITES` / `READS` coverage across the exercised Python, JavaScript, TypeScript, and local-state micro-cases; remaining or out-of-scope gaps: `OVERRIDE` (Go-only) and broader positive `WRITES` / `READS` overlap
  - route nodes — implemented for the graph-model parity fixture contract plus the completed `route-expansion-httpx`, `route-expansion-keyword-request`, and `semantic-expansion-send-task` follow-on fixtures (stub and concrete URL/path/topic `Route` nodes, verified decorator-backed `Route`/`HANDLES`, strict shared route-linked `DATA_FLOWS`, strict shared `ASYNC_CALLS`, route summary exposure, one additional strict shared `httpx` caller slice, zig-only verified keyword route registration and generic `requests.request` slices, and zig-only verified `celery.send_task` topic dispatch; the keyword-route and `send_task` framework slices remain diagnostic-only in the full compare because the current C reference still returns empty row sets there)
  - config-linking — implemented for the graph-model parity fixture contract plus the completed `config-expansion-env-var-python` and `config-expansion-yaml-key-shapes` follow-on fixtures (Strategy 1 key-symbol + Strategy 2 dependency-import, strict shared key-symbol normalization fixture, raw-key preservation, `CONFIGURES` query visibility, Zig dependency-import deduplication coverage, one additional strict shared env-style config-key slice, and a strict shared YAML key-shape slice; broader positive `WRITES` / `READS` overlap remains separate)
  - richer decorator/enrichment promotion
  - completed entrypoint: [graph-model-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/graph-model-parity-plan.md)
- Productization beyond the current contract:
  - broader network-backed or trust-layered self-replacement behavior beyond
    the verified file-backed packaged-archive contract in `update`
  - any future installer side effects beyond the now-verified ten-agent matrix
  - broader post-build security layers beyond the implemented static audit
    suite
  - nightly or multi-hour soak tiers beyond the implemented local soak suite

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
| Session/startup auto-index wiring | Full (checks watcher, triggers if not indexed) | DONE LATER — startup auto-index now supports config or env enablement and has direct startup tests for indexing the current repo plus watcher registration |
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
