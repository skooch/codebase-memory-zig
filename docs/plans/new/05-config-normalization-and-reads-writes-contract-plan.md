# Plan: Config Normalization And Reads Writes Contract

## Goal
Broaden and verify the shared config-linking contract, and decide or prove the next public-harness contract for `WRITES` and `READS`, without regressing the current config normalization and dependency-linking slices.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/05-config-normalization-and-reads-writes-contract-plan.md`
- Create: `docs/plans/new/05-config-normalization-and-reads-writes-contract-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `src/extractor_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/config-expansion-env-var-python.json`
- Modify: `testdata/interop/golden/edge-parity.json`
- Create: `testdata/interop/config-expansion/`
- Create: `testdata/interop/edge-parity/`

## Phases

### Phase 1: Define the next shared config and edge contract
- [ ] Review the current config-linking and edge-parity fixture surface and decide which additional config-key shapes, config languages, or symbol-normalization cases belong in the next shared contract tranche.
- [ ] Probe the current Zig and C behavior for `WRITES` and `READS` on the next candidate micro-cases before assuming those edges have a stable overlap worth promoting into the public harness.
- [ ] Write the exact shared contract target into `docs/plans/in-progress/05-config-normalization-and-reads-writes-contract-progress.md`, including which cases are implementation targets and which remain documented non-overlap.
- **Status:** pending

### Phase 2: Expand config normalization and edge extraction
- [ ] Extend `src/extractor.zig` and `src/pipeline.zig` so the chosen config-language and key-shape cases normalize and link to code symbols consistently with the intended shared contract.
- [ ] If the Zig and C probe shows stable overlap, extend `src/extractor.zig`, `src/pipeline.zig`, `src/store_test.zig`, and `src/extractor_test.zig` so the next `WRITES` or `READS` cases are extracted, resolved, and regression-tested explicitly.
- [ ] Add or extend fixture coverage under `testdata/interop/config-expansion/` and `testdata/interop/edge-parity/` so the broadened config and read/write contract is proven in the public harness.
- **Status:** pending

### Phase 3: Rebaseline docs and interop evidence
- [ ] Refresh the affected manifest entries and goldens only after the new config and read/write slice is verified in zig-only and full-compare runs.
- [ ] Re-run `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`, and record whether config-linking and `WRITES` / `READS` moved from optional debt toward proven shared contract.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the remaining “broader config normalization expansion” language reflects the new measured state.
- [ ] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before execution starts, and to `docs/plans/implemented/` only after the expanded contract is verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep config normalization and `WRITES` / `READS` together | The docs currently present them as one remaining graph-enrichment gap, and both depend on careful contract definition rather than broad feature guessing. |
| Probe C overlap before promising new public-harness edges | The earlier parity work already showed that some read/write cases do not have a stable shared overlap. |
| Prefer explicit fixture cases over generalized symbolic inference claims | The remaining debt here is contract-definition-sensitive and should be proven with small stable fixtures. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
