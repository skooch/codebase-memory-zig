# Progress

## Session: 2026-04-10

- Reworked the remaining interoperability items into execution-ready phases with explicit file targets, acceptance criteria, and dependency order after the tree-sitter runtime blocker was removed.

### Phase 1: Lock the Interoperability Contract
- **Status:** complete
- Actions:
  - Created the tracked checklist plan for interoperability alignment readiness.
  - Captured the minimum vertical slice to complete before starting meaningful cross-implementation alignment tests.
  - Updated `docs/zig-port-plan.md` and `docs/gap-analysis.md` with readiness-scope and cut/defer expectations.
- Files modified:
  - `docs/zig-port-plan.md`
  - `docs/gap-analysis.md`
  - `docs/plans/in-progress/interoperability-alignment-readiness-plan.md`
  - `docs/plans/in-progress/interoperability-alignment-readiness-progress.md`
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `src/registry.zig`
  - `src/cypher.zig`
  - `src/mcp.zig`
  - `src/main.zig`
  - `src/graph_buffer.zig`
  - `src/discover.zig`
- Checklist status:
  - [x] Scope and exclusions captured.
  - [x] Comparison and ordering rules documented.
  - [x] Plan moved into progress tracking.

### Phase 2: Finish Parser-Backed Extraction Parity
- **Status:** complete
- Actions:
  - Implemented pipeline end-to-end execution path from file discovery through graph persistence.
  - Added heuristic extraction of symbols/calls/imports/semantic hints for Rust, Zig, Python, and JavaScript/TS.
  - Implemented registry-based symbol resolution with import-context support.
  - Persisted registry-resolved imports/calls/semantic edges from GraphBuffer into SQLite store.
  - Fixed extraction and pipeline cleanup paths so errors do not leak memory.
  - Added regression coverage for cross-file Python call-edge persistence.
  - Fixed graph buffer node/edge ID handling so edge allocation does not break node lookups.
  - Hardened graph buffer rollback on allocation failures and added allocation-failure regression coverage.
  - Added tree-sitter grammar integration scaffolding and C headers in `vendored/tree_sitter`.
  - Added initial tree-sitter-backed definition extraction for Rust, Zig, Python, and JS/TS with line-anchored fallback for unsupported parsing cases.
  - Fixed the tree-sitter Python runtime crash by aligning the local compatibility header with the actual linked tree-sitter runtime layout while keeping compatibility aliases for older generated grammars.
  - Fixed temporary tree-sitter extraction leaks so the new parser-backed path passes the current Zig test suite cleanly.
  - Added language-scoped parser-backed definition assertions for Python, JavaScript, TypeScript, TSX, Rust, and Zig start lines.
  - Added parser-backed end-to-end pipeline/store regression coverage for `CONTAINS`, `CALLS`, `INHERITS`, and `IMPLEMENTS`.
  - Documented parser-default versus heuristic/unsupported extraction behavior in readiness alignment docs.
- Files modified:
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `src/store_test.zig`
  - `src/registry.zig`
  - `src/graph_buffer.zig`
  - `docs/zig-port-plan.md`
  - `docs/gap-analysis.md`
- Checklist status:
  - [x] Discovery + extraction orchestration in one run.
  - [x] Registry population and candidate resolution.
  - [x] Persisted nodes/edges for queryability.
  - [x] Parser-backed definitions validated for all target languages in extractor and pipeline/store regression coverage.

### Phase 3: Minimum Public Surface
- **Status:** complete
- Actions:
  - Implemented MCP request handling for initialize, tools/list, and tools/call.
  - Added `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`.
  - Confirmed required store query/path methods are available.
  - Implemented CLI single-tool call path and ready-to-run stdio server defaults.
- Files modified:
  - `src/mcp.zig`
  - `src/main.zig`
  - `src/cypher.zig`
  - `src/store.zig`
- Checklist status:
  - [x] 5 tool handlers available.
  - [x] Query responses serializable.
  - [x] CLI entry points usable for automation.

### Phase 4: Define the Alignment Comparison Contract
- **Status:** complete
- Actions:
  - Documented the per-tool output contracts and deterministic comparison normalization rules in `docs/zig-port-plan.md`.
  - Documented tolerated vs hard-failure drift categories in `docs/gap-analysis.md`.
  - Defined ignored fields and acceptance criteria so harness diffs can be interpreted without heuristic overrides.
- Checklist status:
  - [x] Write per-tool comparison rules for the five readiness-scope tools.
  - [x] Document tolerated and disallowed drift categories.
  - [x] Define harness-ready pass/fail criteria.

### Phase 5: Create the First Alignment Fixture Corpus
- **Status:** complete
- Actions:
  - Added `testdata/interop/python-basic`, `javascript-basic`, `typescript-basic`, `rust-basic`, and `zig-basic` fixtures.
  - Added `testdata/interop/manifest.json` with per-fixture tool coverage and expected graph behaviors.
  - Updated readiness plan/checklist status to mark Phase 5 as complete.
- Checklist status:
  - [x] Create Python, JavaScript, TypeScript, Rust, and Zig readiness fixtures.
  - [x] Add a fixture manifest with expected coverage/assertions.
  - [x] Ensure every target language is represented by at least one committed fixture repo.

### Phase 6: Automate the Alignment Diff and Record the Baseline
- **Status:** complete
- Actions:
  - Ran the interoperability harness: `bash scripts/run_interop_alignment.sh`.
  - Harness executed both implementations against the `python-basic`, `javascript-basic`, `typescript-basic`, `rust-basic`, and `zig-basic` fixtures from `testdata/interop/manifest.json`.
  - Captured baseline artifacts in `.interop_reports/interop_alignment_report.json` and `.interop_reports/interop_alignment_report.md`.
  - Baseline mismatch summary:
    - Total fixtures: 5
    - Total comparisons: 25
    - Matches: 12
    - Mismatches: 3
    - Grouped mismatches: `javascript-basic` (search_graph), `typescript-basic` (search_graph), `rust-basic` (search_graph).
- Files modified/created:
  - `scripts/run_interop_alignment.sh` (created earlier; now verified in phase execution).
- Checklist status:
  - [x] Add the alignment harness script.
  - [x] Normalize tool output before diffing.
  - [x] Emit grouped mismatch categories by fixture and tool.
  - [x] Run the harness on the full fixture corpus and record mismatch categories.
  - [ ] Update `docs/zig-port-plan.md` and `docs/gap-analysis.md` based on baseline deltas if needed.
  - [x] Keep a repeatable baseline run available for follow-up.

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-10T20:00:00+11:00 | `zig build test` failed with `Segmentation fault` in `_ts_parser__lex` when parsing Python via tree-sitter. | Added vendored tree-sitter scanners/parsers and parse path for Rust/Python/JS/Zig. | Resolved by correcting the local `parser.h` compatibility shim so `TSLexMode` matches the linked tree-sitter runtime layout; follow-up leak cleanup restored a clean `zig build test`.
