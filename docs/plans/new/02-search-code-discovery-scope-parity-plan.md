# Plan: Search Code Discovery Scope Parity

## Goal
Resolve the documented `search_code` discovery-scope divergence so ignored and generated files are handled according to one measured, intentionally claimed shared contract.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/02-search-code-discovery-scope-parity-plan.md`
- Create: `docs/plans/new/02-search-code-discovery-scope-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `src/discover.zig`
- Modify: `src/search_index.zig`
- Modify: `src/query_router.zig`
- Modify: `src/query_router_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/discovery-scope.json`
- Modify: `testdata/interop/discovery-scope/`

## Phases

### Phase 1: Define the intended indexed-scope contract
- [ ] Re-run the `discovery-scope` fixture in zig-only and full-compare modes and capture the exact path-level disagreement on ignored and generated files.
- [ ] Inspect `src/discover.zig`, `src/search_index.zig`, and `src/query_router.zig` to determine whether the divergence comes from indexing scope, search filtering, or compare expectations.
- [ ] Write the intended post-fix contract into `docs/plans/in-progress/02-search-code-discovery-scope-parity-progress.md`, including whether Zig, C, or the shared manifest should move.
- **Status:** pending

### Phase 2: Align discovery scope and `search_code`
- [ ] Adjust discovery, indexing, or `search_code` filtering so the exercised ignored/generated-file cases follow one explicit contract end to end.
- [ ] Add or tighten `src/query_router_test.zig` coverage for nested ignores, generated paths, and files-only output on the discovery fixture.
- [ ] Refresh `testdata/interop/manifest.json` and `testdata/interop/golden/discovery-scope.json` only after the chosen contract is green in the harness.
- **Status:** pending

### Phase 3: Rebaseline parity claims
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the `search_code` row reflects the new measured state.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the measured divergence is either removed or restated from fresh evidence.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan limited to the discovery-scope fixture contract | The documented problem is bounded and should stay measurable. |
| Treat indexed-scope semantics as more important than incidental ranking behavior | The current disagreement is about which files appear at all, not result ordering polish. |
| Use fixture-backed evidence to choose the final claim | This row should be updated from the harness, not from local preference. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
