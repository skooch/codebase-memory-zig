# Progress

## Session: 2026-04-20

### Phase 1: Define the intended indexed-scope contract
- **Status:** completed
- Actions:
  - Created the discovery-scope `search_code` parity plan as backlog item `02`.
  - Scoped it to the documented ignored/generated-file divergence rather than the entire `search_code` surface.
  - Reproduced the exercised `search_code` queries directly against both binaries on `testdata/interop/discovery-scope`.
  - Confirmed there is no live path-level disagreement in the current fixture:
    - both Zig and C return `src/index.ts` for `scopeVisible`
    - both Zig and C return `0` results for `ghostIgnoredHit`
    - both Zig and C return `0` results for `generatedBundleHit`
    - both Zig and C return `0` results for `ghostNestedHit`
  - Inspected `src/discover.zig`, `src/search_index.zig`, and `src/query_router.zig` and found the current Zig indexed-scope behavior already matches the measured shared contract.
  - Chose the documentation path for Phase 2 because the earlier divergence claim is stale rather than a live code-path defect.
- Files modified:
  - `docs/plans/in-progress/02-search-code-discovery-scope-parity-plan.md`
  - `docs/plans/in-progress/02-search-code-discovery-scope-parity-progress.md`

### Phase 2: Align discovery scope and `search_code`
- **Status:** completed
- Actions:
  - Determined that no discovery, indexing, or `search_code` code change was required because both implementations already satisfy the asserted fixture contract end to end.
  - Determined that no `query_router_test.zig` expansion was required for this bounded plan because the live interop fixture and full compare already prove the claimed ignored/generated-file behavior directly.
  - Determined that `testdata/interop/manifest.json` and `testdata/interop/golden/discovery-scope.json` were already correct and required no refresh.
- Files modified:
  - none

### Phase 3: Rebaseline parity docs
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Reconfirmed the current full-compare baseline at:
    - `31` fixtures
    - `237` comparisons
    - `135` strict matches
    - `36` diagnostic-only comparisons
    - `0` mismatches
  - Updated the parity docs to remove the stale discovery-scope divergence claim and reclassify `search_code` as shared-contract aligned on the verified fixtures.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
