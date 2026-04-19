# Plan: Search And Snippet Contract Normalization

## Goal
Normalize `search_graph` and `get_code_snippet` behavior so the Zig port reduces remaining payload-shape and selection-semantics drift against the C reference without regressing the current daily-use contract.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/03-search-and-snippet-contract-normalization-plan.md`
- Create: `docs/plans/new/03-search-and-snippet-contract-normalization-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `src/query_router.zig`
- Modify: `src/store.zig`
- Modify: `src/mcp.zig`
- Modify: `src/query_router_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/python-parity.json`
- Modify: `testdata/interop/golden/go-basic.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Modify: `testdata/interop/golden/zig-parity.json`
- Modify: `testdata/interop/golden/error-paths.json`

## Phases

### Phase 1: Define the desired shared contract
- [ ] Reproduce and catalog the current `search_graph` and `get_code_snippet` deltas from the full Zig-vs-C compare, including the fixture, payload field, and selection behavior involved in each mismatch.
- [ ] Decide which differences belong in implementation, which belong in harness canonicalization, and which remain intentional API-shape differences that should be documented instead of “fixed”.
- [ ] Write the exact normalization target into `docs/plans/in-progress/03-search-and-snippet-contract-normalization-progress.md` before implementation starts.
- **Status:** pending

### Phase 2: Normalize search and snippet behavior
- [ ] Update `src/query_router.zig`, `src/store.zig`, and `src/mcp.zig` so `get_code_snippet` returns the intended shared fields, source fragments, and suggestion semantics on the currently divergent cases.
- [ ] Update `src/store.zig`, `src/query_router.zig`, and `scripts/run_interop_alignment.sh` so `search_graph` ranking, label handling, and canonicalization converge toward the intended shared contract on the currently divergent cases.
- [ ] Add regression coverage in `src/query_router_test.zig` and `src/mcp.zig` for the normalized snippet and search behaviors so the harness is not the first line of detection.
- **Status:** pending

### Phase 3: Rebaseline and document the contract
- [ ] Refresh the affected fixture expectations and goldens in `testdata/interop/manifest.json` and `testdata/interop/golden/*.json` only after the normalized behavior is proven in both zig-only and full-compare runs.
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`, and record the reduced or remaining search/snippet mismatch set.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/interop-testing-review.md` so the remaining search/snippet debt is described precisely.
- [ ] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the normalized contract is verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep `search_graph` and `get_code_snippet` together in one plan | The current remaining deltas cluster around query-router payload shaping and selection semantics, so one shared normalization slice is cleaner than splitting them. |
| Explicitly separate implementation work from harness canonicalization work | Some remaining differences may be purely representational rather than semantic. |
| Use fixture-backed proof for every normalized behavior | These tools are directly user-facing, so regressions should be locked down close to the current mismatch cases. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
