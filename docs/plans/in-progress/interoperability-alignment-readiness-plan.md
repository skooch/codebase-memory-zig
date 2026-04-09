# Plan: Interoperability Alignment Readiness

## Goal
Define and complete the minimum Zig-port work needed before an alignment test suite can usefully compare this implementation against the original `codebase-memory-mcp`.

## Current Phase
Phase 2

## File Map
- Modify: `docs/zig-port-plan.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/registry.zig`
- Modify: `src/store.zig`
- Modify: `src/mcp.zig`
- Modify: `src/cypher.zig`
- Modify: `src/watcher.zig`
- Modify: `src/main.zig`

## Phases

### Phase 1: Lock the Interoperability Contract
- [x] Document the first alignment-test scope as `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`.
- [x] Document that CUT and DEFER items are excluded from alignment expectations until explicitly promoted.
- [x] Define comparison rules that normalize paths, ignore unstable internal IDs, and require deterministic result ordering.
- [x] Update `docs/zig-port-plan.md` and `docs/gap-analysis.md` to reflect the alignment-readiness target state.
- [ ] Record explicit “alignment mismatch contract” (allowed semantic drift) for each supported tool.
- **Status:** complete

### Phase 2: Complete the Minimum Indexing Vertical Slice
- [x] Complete `src/pipeline.zig` so the pipeline performs discovery, extraction, registry population, edge resolution, and graph-buffer-to-store persistence in one run.
- [x] Complete `src/registry.zig` so call resolution uses symbol definitions plus import context.
- [x] Implement the minimum pass-equivalent behavior needed for alignment in `src/pipeline.zig`: definition nodes, call edges, and semantic edges.
- [x] Confirm the resulting index of a small repo produces persisted nodes and edges that can be queried from `src/store.zig`.
- [ ] Replace the current heuristic extraction with tree-sitter-backed definition extraction for Rust, Zig, Python, and JS/TS.
- **Status:** in_progress

### Phase 3: Complete the Minimum Public Surface for Comparison
- [x] Implement JSON-RPC request parsing, response formatting, initialize handling, and `tools/list` in `src/mcp.zig`.
- [x] Implement tool handlers for `index_repository`, `search_graph`, `query_graph`, `trace_call_path`, and `list_projects`.
- [x] Complete the supporting `src/store.zig` query and traversal operations required by those five tool handlers.
- [x] Complete the executable entrypoints in `src/main.zig` needed to run the MCP server and invoke a single tool call for test automation.
- [x] Decide whether `src/watcher.zig` is required for first-suite parity (out-of-scope now, deferred).
- **Status:** complete

### Phase 4: Make Alignment Testing High-Signal
- [ ] Create a fixture corpus that covers Rust, Zig, Python, and JS/TS repositories with expected graph behaviors.
- [ ] Define expected comparisons at the semantic level: nodes, labels, names, qualified names, edge types, and traversal results.
- [ ] Document tolerated differences between the original and Zig port that do not violate interoperability goals.
- [ ] Add an automated harness that runs the same inputs through both implementations and reports meaningful diffs.
- [ ] Run the first alignment pass and capture the initial mismatch categories before broadening feature coverage.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Track this as a separate plan in `docs/plans/in-progress/` | The work is broader than a single code fix and needs a durable checklist before implementation starts. |
| Treat interoperability as a vertical-slice milestone, not a full-port milestone | Alignment tests become useful once the core indexing + query path exists, even if deferred features are still unfinished. |

## Phase Deliverables
- **Phase 1 (done):** Scope, exclusions, and comparison rules are now explicit in implementation docs.
- **Phase 2 (in_progress):** Indexing pipeline persists to store and resolves calls/semantics with registry context.
- **Phase 3 (done):** Command entrypoints and MCP tools are callable for readiness-level alignment smoke checks.
- **Phase 4 (not_started):** No fixture corpus or comparison harness yet; this is the next execution block.

## Errors
| Error | Attempt | Resolution |

## Plan Checklist
- [x] **Phase 1 complete** — interoperability scope, exclusions, and deterministic comparison rules are documented.
- [ ] **Phase 1 stretch goal complete** — per-tool alignment mismatch contract is still not explicitly written down.
- [x] **Phase 2 vertical slice works** — discovery, extraction retention, registry resolution, and persisted call/import/semantic edges are working end-to-end.
- [x] **Phase 2 hardening landed** — cross-file call-edge regression coverage exists and graph-buffer ID / allocation rollback bugs found during review have been fixed.
- [ ] **Phase 2 parity complete** — heuristic extraction is still in place; tree-sitter-backed Rust/Zig/Python/JS extraction remains outstanding.
- [x] **Phase 3 complete** — the five readiness-scope MCP tools and automation entrypoints are available.
- [ ] **Phase 4 complete** — fixture corpus, semantic diff harness, and first mismatch pass are still outstanding.
