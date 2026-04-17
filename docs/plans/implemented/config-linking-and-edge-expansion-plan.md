# Plan: Config Linking And Edge Expansion Follow-On

## Status
Completed on 2026-04-17. This
plan was resumed from the former paused/superseded config-linking plan and
narrowed to the remaining config/edge work after
`docs/plans/implemented/graph-model-parity-plan.md`.

Already complete for the verified graph-model fixture contract: key-symbol
config linking, raw config-key preservation, dash/camel normalization,
`CONFIGURES` query visibility, and Zig dependency-import deduplication coverage.

## Goal
Expand config-linking and long-tail edge coverage only where there is a real,
verifiable overlap with the original C implementation. Avoid reviving broad
`WRITES` / `READS` parity claims until the C reference exposes matching public
fixture rows.

## Current Phase
Complete. The config / edge follow-on now has one additional strict shared
fixture for env-style config keys, targeted normalization coverage in
`src/pipeline.zig`, and a full-harness confirmation that no new config-related
mismatches were introduced. `WRITES` / `READS` remain unproven and stay outside
strict parity claims.

## File Map
- Modify:
  `docs/plans/implemented/config-linking-and-edge-expansion-plan.md`
- Create/modify:
  `docs/plans/implemented/config-linking-and-edge-expansion-progress.md`
- Likely modify: `src/extractor.zig`
- Likely modify: `src/pipeline.zig`
- Likely modify: `src/graph_buffer.zig`
- Likely modify: `src/store.zig`
- Likely modify: `src/cypher.zig`
- Likely modify: `testdata/interop/manifest.json`
- Potentially create fixtures under `testdata/interop/config-expansion/`

## Phases

### Phase 1: Lock The Config / Edge Contract
- [x] Re-probe current C and Zig behavior for config-language/key-shape
  candidates before adding assertions.
- [x] Separate three buckets explicitly:
  verified shared rows, useful Zig-only rows, and C-empty/unproven rows.
- [x] Identify whether any `WRITES` / `READS` candidate can be proven as a true
  original-overlap public fixture row.
- [x] Record accepted rows, rejected candidates, and exact verification commands
  in
  `docs/plans/implemented/config-linking-and-edge-expansion-progress.md`.
- **Status:** complete

### Phase 2: Implement Narrow Expansion
- [x] Extend config-key normalization or dependency-import matching only where a
  fixture proves the behavior is useful and query-visible.
- [x] Keep edge insertion deduplicated and preserve current `CONFIGURES`
  behavior.
- [x] Add focused tests for any new config key shape, manifest format, or edge
  label promoted by Phase 1.
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] Run `zig fmt` on touched Zig files.
- [x] Run `zig build test`.
- [x] Run `zig build`.
- [x] Run `bash scripts/run_interop_alignment.sh --zig-only`.
- [x] Run `bash scripts/run_interop_alignment.sh` and confirm any new strict
  config/edge assertions are green.
- [x] Update `docs/port-comparison.md` / `docs/gap-analysis.md` only as far as
  the evidence supports.
- **Status:** complete

## Acceptance Rules
- A config or edge row can become a strict interop assertion only after both
  current C and Zig binaries expose the same row shape on the same local fixture.
- Empty C results do not prove parity for new Zig behavior.
- The plan is complete only after the full harness has no new config/edge
  mismatches and the docs record any remaining unproven long-tail edge families.

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start after route graph follow-on | Route expansion is now complete, and config expansion remains the next highest-value enrichment slice. Several candidate C fixtures still return empty rows, so this phase stays evidence-led. |
| Keep `WRITES` / `READS` out until proven | The current docs already record that these rows are not proven original-overlap by the C reference fixture. |
| Preserve existing `CONFIGURES` contract | Graph-model parity locked key-symbol normalization and dependency-import deduplication; follow-on work must not churn that baseline. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
