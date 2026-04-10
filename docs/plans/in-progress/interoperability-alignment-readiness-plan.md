# Plan: Interoperability Alignment Readiness

## Goal
Define and complete the minimum Zig-port work needed before an alignment test suite can usefully compare this implementation against the original `codebase-memory-mcp`.

## Current Phase
Phase 4

## File Map
- Modify: `docs/plans/in-progress/interoperability-alignment-readiness-plan.md`
- Modify: `docs/plans/in-progress/interoperability-alignment-readiness-progress.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Create: `testdata/interop/manifest.json`
- Create: `testdata/interop/python-basic/main.py`
- Create: `testdata/interop/python-basic/util.py`
- Create: `testdata/interop/javascript-basic/index.js`
- Create: `testdata/interop/typescript-basic/index.ts`
- Create: `testdata/interop/rust-basic/src/lib.rs`
- Create: `testdata/interop/zig-basic/main.zig`
- Create: `scripts/run_interop_alignment.sh`

## Phases

### Phase 1: Lock the Interoperability Contract
- [x] Document the first alignment-test scope as `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`.
- [x] Document that CUT and DEFER items are excluded from alignment expectations until explicitly promoted.
- [x] Define comparison rules that normalize paths, ignore unstable internal IDs, and require deterministic result ordering.
- [x] Update `docs/zig-port-plan.md` and `docs/gap-analysis.md` to reflect the alignment-readiness target state.
- [ ] Record explicit “alignment mismatch contract” (allowed semantic drift) for each supported tool.
- **Status:** complete

### Phase 2: Finish Parser-Backed Extraction Parity
- [x] Complete `src/pipeline.zig` so the pipeline performs discovery, extraction, registry population, edge resolution, and graph-buffer-to-store persistence in one run.
- [x] Complete `src/registry.zig` so call resolution uses symbol definitions plus import context.
- [x] Implement the minimum pass-equivalent behavior needed for alignment in `src/pipeline.zig`: definition nodes, call edges, and semantic edges.
- [x] Confirm the resulting index of a small repo produces persisted nodes and edges that can be queried from `src/store.zig`.
- [x] In `src/extractor.zig`, make tree-sitter the default definition source for `.python`, `.javascript`, `.typescript`, `.tsx`, `.rust`, and `.zig`, with heuristic definition parsing retained only for unsupported languages.
- [x] In `src/extractor.zig`, add language-specific extraction tests that assert extracted symbol `label`, `name`, and `start_line` for at least one representative snippet per target language.
- [x] In `src/pipeline.zig` and `src/store_test.zig`, add end-to-end regression coverage that proves parser-backed definitions survive indexing and produce persisted `CONTAINS`, `CALLS`, `INHERITS`, or `IMPLEMENTS` edges where expected.
- [x] In `docs/zig-port-plan.md` and `docs/gap-analysis.md`, document any extraction behaviors that remain intentionally heuristic, unsupported, or deferred after the parser-backed definition pass is complete.
- [x] Exit this phase only when `zig build test` covers parser-backed extraction for all target languages without relying on the old heuristic definition path.
- **Status:** complete

### Phase 3: Complete the Minimum Public Surface for Comparison
- [x] Implement JSON-RPC request parsing, response formatting, initialize handling, and `tools/list` in `src/mcp.zig`.
- [x] Implement tool handlers for `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`.
- [x] Complete the supporting `src/store.zig` query and traversal operations required by those five tool handlers.
- [x] Complete the executable entrypoints in `src/main.zig` needed to run the MCP server and invoke a single tool call for test automation.
- [x] Decide whether `src/watcher.zig` is required for first-suite parity (out-of-scope now, deferred).
- **Status:** complete

### Phase 4: Define the Alignment Comparison Contract
- [x] In `docs/zig-port-plan.md`, write the per-tool comparison contract for `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`, including required fields, normalization rules, and stable sort expectations.
- [x] In `docs/gap-analysis.md`, list which differences are tolerated during the first interoperability gate and which differences are considered hard failures.
- [x] Specify exactly which fields are ignored during comparison, including internal IDs, watcher side effects, and metadata from CUT or DEFER features.
- [x] Define the acceptance rule for each readiness-scope tool so a harness can score pass/fail without ad-hoc interpretation.
- [x] Exit this phase only when a human reviewer can answer “does this mismatch matter?” by reading the documented contract instead of inferring intent from code.
- **Status:** complete

### Phase 5: Create the First Alignment Fixture Corpus
- [ ] Create `testdata/interop/python-basic/main.py` and `testdata/interop/python-basic/util.py` to cover module imports, function definitions, and a resolved call edge.
- [ ] Create `testdata/interop/javascript-basic/index.js` to cover function/class discovery and inheritance or import-driven call resolution in the JS family.
- [ ] Create `testdata/interop/typescript-basic/index.ts` to cover TS-specific declaration forms that must still normalize to the readiness-scope graph contract.
- [ ] Create `testdata/interop/rust-basic/src/lib.rs` to cover `fn`, `struct`, `trait`, and `impl ... for ...` extraction expectations.
- [ ] Create `testdata/interop/zig-basic/main.zig` to cover function declarations, `@import`, and basic container/type extraction.
- [ ] Create `testdata/interop/manifest.json` that maps each fixture to the tools, graph facts, and comparison assertions it is expected to exercise.
- [ ] Exit this phase only when every target language has at least one committed fixture repo and the manifest states which graph behaviors each fixture must prove.
- **Status:** pending

### Phase 6: Automate the Alignment Diff and Record the Baseline
- [ ] Create `scripts/run_interop_alignment.sh` to run the Zig port and the original `codebase-memory-mcp` against the same fixture corpus using the readiness-scope tools.
- [ ] Make the harness normalize outputs according to the documented comparison contract before diffing, rather than comparing raw JSON directly.
- [ ] Make the harness emit grouped mismatch categories by fixture and tool so failures are actionable instead of noisy.
- [ ] Run the harness on the full fixture corpus and record the initial mismatch categories in `docs/plans/in-progress/interoperability-alignment-readiness-progress.md`.
- [ ] Update `docs/zig-port-plan.md` and `docs/gap-analysis.md` if the first baseline reveals contract gaps or previously unknown tolerated drift categories.
- [ ] Exit this phase only when there is a repeatable baseline run that distinguishes “contract-compliant difference” from “real interoperability defect.”
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Track this as a separate plan in `docs/plans/in-progress/` | The work is broader than a single code fix and needs a durable checklist before implementation starts. |
| Treat interoperability as a vertical-slice milestone, not a full-port milestone | Alignment tests become useful once the core indexing + query path exists, even if deferred features are still unfinished. |

## Phase Deliverables
- **Phase 1 (done):** Scope, exclusions, and comparison rules are now explicit in implementation docs.
- **Phase 2 (complete):** Parser-backed extraction is now the default readiness path for target languages and is covered by parser-regression assertions.
- **Phase 3 (done):** Command entrypoints and MCP tools are callable for readiness-level alignment smoke checks.
- **Phase 4 (complete):** Comparison rules are detailed enough that a harness can score pass/fail without hand-written interpretation.
- **Phase 5 (pending):** A committed cross-language fixture corpus exists with a manifest that states what each fixture proves.
- **Phase 6 (pending):** A repeatable harness run exists and the first mismatch categories have been recorded.

## Plan Checklist
- [x] **Phase 1 complete** — interoperability scope, exclusions, and deterministic comparison rules are documented.
- [ ] **Phase 1 stretch goal complete** — per-tool alignment mismatch contract is still not explicitly written down.
- [x] **Phase 2 vertical slice works** — discovery, extraction retention, registry resolution, and persisted call/import/semantic edges are working end-to-end.
- [x] **Phase 2 hardening landed** — cross-file call-edge regression coverage exists and graph-buffer ID / allocation rollback bugs found during review have been fixed.
- [x] **Phase 2 parity complete** — parser-backed definitions are the default for target languages, and language-specific regression coverage plus explicit deferred-parsing notes exist.
- [x] **Phase 3 complete** — the five readiness-scope MCP tools and automation entrypoints are available.
- [x] **Phase 4 contract complete** — per-tool comparison rules and tolerated drift are documented at harness-ready fidelity.
- [ ] **Phase 5 fixtures complete** — the first cross-language fixture corpus and manifest are committed.
- [ ] **Phase 6 baseline complete** — the alignment harness runs both implementations and records the initial mismatch categories.
- [x] **Runtime stability checkpoint** — the tree-sitter header/runtime compatibility crash is fixed and the current Zig test suite passes again.

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `pipeline` tests crashed with SIGSEGV in `_ts_parser__lex` when parsing a simple Python file using tree-sitter-backed extractors. | Added vendored rust/python/javascript/typescript/tsx/zig parsers and scanner integration; changed extraction path. | Resolved by correcting the local `tree_sitter/parser.h` compatibility shim so `TSLexMode` matches the linked tree-sitter runtime layout; temporary extraction arrays were then cleaned up so `zig build test` passes again.
