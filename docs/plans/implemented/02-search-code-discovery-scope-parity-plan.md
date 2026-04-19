# Plan: Search Code Discovery Scope Parity

## Goal
Resolve the documented `search_code` discovery-scope divergence so ignored and generated files are handled according to one measured, intentionally claimed shared contract.

## Current Phase
Completed

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
- [x] Re-run the `discovery-scope` fixture in zig-only and full-compare modes and capture the exact path-level disagreement on ignored and generated files.
- [x] Inspect `src/discover.zig`, `src/search_index.zig`, and `src/query_router.zig` to determine whether the divergence comes from indexing scope, search filtering, or compare expectations.
- [x] Write the intended post-fix contract into `docs/plans/in-progress/02-search-code-discovery-scope-parity-progress.md`, including whether Zig, C, or the shared manifest should move.
- **Status:** completed

### Phase 2: Align discovery scope and `search_code`
- [x] Adjust discovery, indexing, or `search_code` filtering so the exercised ignored/generated-file cases follow one explicit contract end to end.
- [x] Add or tighten `src/query_router_test.zig` coverage for nested ignores, generated paths, and files-only output on the discovery fixture.
- [x] Refresh `testdata/interop/manifest.json` and `testdata/interop/golden/discovery-scope.json` only after the chosen contract is green in the harness.
- **Status:** completed

### Phase 3: Rebaseline parity claims
- [x] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
- [x] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the `search_code` row reflects the new measured state.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the measured divergence is either removed or restated from fresh evidence.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan limited to the discovery-scope fixture contract | The documented problem is bounded and should stay measurable. |
| Treat indexed-scope semantics as more important than incidental ranking behavior | The current disagreement is about which files appear at all, not result ordering polish. |
| Use fixture-backed evidence to choose the final claim | This row should be updated from the harness, not from local preference. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
