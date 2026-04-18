# Plan: Discovery, Indexing Scope, and Query Semantics Improvements

## Goal
Align the Zig port’s discovery and query contract with the upstream lessons around what should be indexed, what should be ignored, and how search and schema tools should behave when scope is ambiguous.

## Research Basis

Upstream issue families captured in this plan:
- Ignore rules and scope boundaries: `#31`, `#44`, `#48`, `#51`, `#71`, `#178`, `#234`
- Search correctness against indexed data: `#102`, `#180`, `#200`, `#201`
- Query semantics and schema shape: `#26`, `#54`, `#154`, `#179`

Upstream PRs that show the likely implementation shape:
- Discovery and ignore behavior: `#37`, `#183`
- Query-limit and explicit-limit fixes: `#40`, `#231`
- Search scope and ghost-store fixes: `#103`, `#120`, `#155`
- Config and path surfaces that influence discovery: `#60`, `#73`, `#173`
- Schema-property follow-on: `#181`
- Import-resolution follow-on: `#184`

Observed upstream pattern:
- Users treat search and schema tools as contract surfaces, not best-effort helpers.
- A large share of “bad search result” reports were caused by indexing things that should have been skipped or by returning results with incomplete scope metadata.

## Current Phase
Complete

## File Map
- Modify: `docs/plans/implemented/discovery-indexing-scope-and-query-semantics-improvements-plan.md`
- Create: `docs/plans/implemented/discovery-indexing-scope-and-query-semantics-improvements-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/discover.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/search_index.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/mcp.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Create: `testdata/interop/discovery-scope/.gitignore`
- Create: `testdata/interop/discovery-scope/src/index.ts`
- Create: `testdata/interop/discovery-scope/vendor/ignored.js`
- Create: `testdata/interop/discovery-scope/.worktrees/duplicate.ts`

## Phases

### Phase 1: Lock the Scope and Query Contract
- [x] Capture the expected ignore semantics, search-only-indexed-files rule, schema-property expectations, and query-limit behavior in `docs/gap-analysis.md`.
- [x] Add a local discovery-scope fixture with ignored, duplicated, and generated-style paths so search and schema behavior can be verified without external repos.
- [x] Record exact `search_graph`, `search_code`, `get_graph_schema`, and `list_projects` verification commands in `docs/plans/implemented/discovery-indexing-scope-and-query-semantics-improvements-progress.md`.
- **Status:** complete

### Phase 2: Implement Deterministic Scope Rules
- [x] Extend `src/discover.zig` so nested ignore handling and negated root
  patterns behave deterministically during recursive discovery.
- [x] Tighten `src/query_router.zig`, `src/store.zig`, and `src/mcp.zig` so
  fallback search operates only on indexed content and schema language counts
  come from indexed project file paths.
- [x] Update `scripts/run_interop_alignment.sh` and
  `testdata/interop/manifest.json` to include the discovery-scope fixture
  queries and file-mode assertions.
- **Status:** complete

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and
  `bash scripts/run_interop_alignment.sh` on the discovery-scope-enabled
  harness.
- [x] Update `docs/port-comparison.md` only for rows whose discovery and search
  semantics are now fixture-backed.
- [x] Record the remaining disagreement with the current C reference in the
  progress log at
  `docs/plans/implemented/discovery-indexing-scope-and-query-semantics-improvements-progress.md`
  instead of masking it as parity.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat “indexed scope” as a first-class contract | The upstream backlog shows that search quality depends as much on discovery boundaries as on ranking logic. |
| Land schema and query-shape fixes alongside scope fixes | Better schema metadata only helps if it accurately reflects the indexed universe. |
| Keep `get_graph_schema` and `list_projects` payload growth minimal | The new fixture justified schema-language correctness and stable project listing, but it did not justify adding more explanatory payload surface yet. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `search_code` files-mode assertions initially looked red for the visible-file case | The harness only canonicalized `results[]`, but files mode returns `files[]` | Normalize files-mode payloads in `scripts/run_interop_alignment.sh` before interpreting the discovery-scope result. |
| `get_graph_schema` contract checks initially misread label/type rows | The harness treated `node_labels` and `edge_types` as string arrays instead of dict arrays | Canonicalize schema label/type entries by their `label` and `type` keys. |
