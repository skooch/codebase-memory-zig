# Progress

## Session: 2026-04-09

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

### Phase 2: Minimum Indexing Vertical Slice
- **Status:** complete
- Actions:
  - Implemented pipeline end-to-end execution path from file discovery through graph persistence.
  - Added heuristic extraction of symbols/calls/imports/semantic hints for Rust, Zig, Python, and JavaScript/TS.
  - Implemented registry-based symbol resolution with import-context support.
  - Persisted registry-resolved imports/calls/semantic edges from GraphBuffer into SQLite store.
  - Fixed extraction and pipeline cleanup paths so errors do not leak memory.
- Files modified:
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `src/registry.zig`
  - `src/graph_buffer.zig`
- Checklist status:
  - [x] Discovery + extraction orchestration in one run.
  - [x] Registry population and candidate resolution.
  - [x] Persisted nodes/edges for queryability.
  - [ ] Tree-sitter-backed extraction replacement (heuristic parser remains).

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

### Phase 4: Alignment Validation
- **Status:** not_started
- Actions:
  - No fixture corpus added yet.
  - No cross-implementation harness wired yet.
- Checklist status:
  - [ ] Create cross-language fixture corpus.
  - [ ] Add deterministic expected-result matcher.
  - [ ] Run baseline mismatch pass and categorize differences.

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
