# Discovery, Indexing Scope, and Query Semantics Progress

## Scope

This plan makes indexed scope and query semantics explicit enough that search
results and schema output can explain what the Zig port indexed, skipped, and
reported.

Current focus:
- ignore-rule and scope-boundary behavior
- search-only-indexed-files behavior
- schema and project-list payload shape for scope explanation

## Phase 1 Contract

### Current baseline from the implementation

- `discoverFiles()` currently loads root `.gitignore` and `.cbmignore`, then
  recurses from that initial rule set.
- `search_code` currently falls back to a fresh filesystem discovery walk when
  the indexed candidate-path search returns no hits.
- `get_graph_schema` returns status plus aggregate counts for labels, edge
  types, and languages, but not relationship patterns or properties.
- `list_projects` returns every stored project with counts and root path, but no
  scope explanation for duplicated or skipped paths.

### Fixture inventory

- `testdata/interop/discovery-scope/.gitignore`
  - Ignore `vendor/`, `generated/`, and `.worktrees/`
- `testdata/interop/discovery-scope/src/index.ts`
  - Indexed file that should remain searchable
- `testdata/interop/discovery-scope/vendor/ignored.js`
  - Ignored file that must not be searchable
- `testdata/interop/discovery-scope/.worktrees/duplicate.ts`
  - Worktree-shaped path that must not leak into indexed scope
- `testdata/interop/discovery-scope/generated/bundle.js`
  - Generated-style path that should remain out of indexed search results
- `testdata/interop/discovery-scope/src/nested/.gitignore`
  - Nested ignore file for a red-case lane the current implementation does not
    yet honor
- `testdata/interop/discovery-scope/src/nested/ghost.js`
  - Nested ignored file that should disappear once nested ignore loading exists

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_interop_alignment.sh
```

Direct MCP checks to lock the contract:

```sh
zig build run -- cli index_repository '{"project_path":"testdata/interop/discovery-scope","mode":"full"}'
zig build run -- cli search_graph '{"project":"discovery-scope","label":"Function"}'
zig build run -- cli search_code '{"project":"discovery-scope","pattern":"scopeVisible","mode":"files","limit":20}'
zig build run -- cli search_code '{"project":"discovery-scope","pattern":"ghostIgnoredHit","mode":"files","limit":20}'
zig build run -- cli search_code '{"project":"discovery-scope","pattern":"ghostNestedHit","mode":"files","limit":20}'
zig build run -- cli get_graph_schema '{"project":"discovery-scope"}'
zig build run -- cli list_projects '{}'
```

Expected assertions:
- `search_code(scopeVisible)` must only report `src/index.ts`.
- `search_code(ghostIgnoredHit)` must report no results after the scope fix.
- `search_code(ghostNestedHit)` currently exposes the nested-ignore gap and
  should report no results once nested ignore loading is implemented.
- `get_graph_schema` must at least continue to identify the project and its
  current label/type counts while Phase 2 expands explanatory metadata.
- `list_projects` must keep returning `name`, `indexed_at`, and `root_path` and
  should later gain clearer scope explanation instead of silent duplication.

## Phases

### Phase 1: Lock the Scope and Query Contract
- [x] Captured the expected ignore semantics, search-only-indexed-files rule,
  schema payload expectations, and project-list scope expectations in
  `docs/gap-analysis.md`.
- [x] Added the local discovery-scope fixture with ignored, duplicated, and
  generated-style paths.
- [x] Recorded the exact `search_graph`, `search_code`, `get_graph_schema`, and
  `list_projects` verification commands in this progress file.
- **Status:** complete

### Phase 2: Implement Deterministic Scope Rules
- [ ] Make discovery respect the intended ignore and scope boundaries.
- [ ] Stop `search_code` from reading outside the indexed universe.
- [ ] Expand schema and project-list payloads only where they help explain
  indexed scope and query results.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Add the discovery-scope fixture assertions to the interop harness.
- [ ] Re-run the harness plus direct MCP checks until the discovery-scope
  contract is stable.
- [ ] Reclassify only the discovery/search/schema rows that now have
  fixture-backed evidence.
- **Status:** pending

## Initial Baseline Probe

Controlled probe run on 2026-04-18 before Phase 2 code changes:

- `index_repository(discovery-scope)` returned `nodes=5`, `edges=4`
- `search_graph(label=Function)` returned only `scopeVisible`
- `search_code(scopeVisible)` returned only `src/index.ts`
- `search_code(ghostIgnoredHit)` returned no rows
- `search_code(generatedBundleHit)` returned no rows
- `get_graph_schema(discovery-scope)` returned project status and counts, but the
  `languages` field contained node labels (`File`, `Folder`, `Function`,
  `Module`, `Project`) instead of source-language information
- `list_projects()` returned the single indexed project with `name`,
  `indexed_at`, `root_path`, `nodes`, and `edges`

What this baseline means:
- root-level ignore handling for `vendor/`, `generated/`, and `.worktrees/` is
  already working on the local fixture
- the schema payload still has at least one concrete correctness issue in its
  `languages` output
- the nested-ignore lane is the next explicit red-case probe for Phase 2
