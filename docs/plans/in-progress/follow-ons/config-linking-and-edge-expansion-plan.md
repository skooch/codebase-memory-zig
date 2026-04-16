# Plan: Config Linking And Edge Expansion Follow-On

## Status
In progress as of 2026-04-16, but queued behind the route graph follow-on. This
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
Queued. Start after the route graph follow-on reaches verification.

## File Map
- Modify:
  `docs/plans/in-progress/follow-ons/config-linking-and-edge-expansion-plan.md`
- Create/modify:
  `docs/plans/in-progress/follow-ons/config-linking-and-edge-expansion-progress.md`
- Likely modify: `src/extractor.zig`
- Likely modify: `src/pipeline.zig`
- Likely modify: `src/graph_buffer.zig`
- Likely modify: `src/store.zig`
- Likely modify: `src/cypher.zig`
- Likely modify: `testdata/interop/manifest.json`
- Potentially create fixtures under `testdata/interop/config-expansion/`

## Phases

### Phase 1: Lock The Config / Edge Contract
- [ ] Re-probe current C and Zig behavior for config-language/key-shape
  candidates before adding assertions.
- [ ] Separate three buckets explicitly:
  verified shared rows, useful Zig-only rows, and C-empty/unproven rows.
- [ ] Identify whether any `WRITES` / `READS` candidate can be proven as a true
  original-overlap public fixture row.
- [ ] Record accepted rows, rejected candidates, and exact verification commands
  in
  `docs/plans/in-progress/follow-ons/config-linking-and-edge-expansion-progress.md`.
- **Status:** queued

### Phase 2: Implement Narrow Expansion
- [ ] Extend config-key normalization or dependency-import matching only where a
  fixture proves the behavior is useful and query-visible.
- [ ] Keep edge insertion deduplicated and preserve current `CONFIGURES`
  behavior.
- [ ] Add focused tests for any new config key shape, manifest format, or edge
  label promoted by Phase 1.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig fmt` on touched Zig files.
- [ ] Run `zig build test`.
- [ ] Run `zig build`.
- [ ] Run `bash scripts/run_interop_alignment.sh --zig-only`.
- [ ] Run `bash scripts/run_interop_alignment.sh` and confirm any new strict
  config/edge assertions are green.
- [ ] Update `docs/port-comparison.md` / `docs/gap-analysis.md` only as far as
  the evidence supports.
- **Status:** pending

## Acceptance Rules
- A config or edge row can become a strict interop assertion only after both
  current C and Zig binaries expose the same row shape on the same local fixture.
- Empty C results do not prove parity for new Zig behavior.
- The plan is complete only after the full harness has no new config/edge
  mismatches and the docs record any remaining unproven long-tail edge families.

## Decisions
| Decision | Rationale |
|----------|-----------|
| Queue behind route graph follow-on | Config expansion is valuable but historically easier to overclaim because several candidate C fixtures return empty rows. |
| Keep `WRITES` / `READS` out until proven | The current docs already record that these rows are not proven original-overlap by the C reference fixture. |
| Preserve existing `CONFIGURES` contract | Graph-model parity locked key-symbol normalization and dependency-import deduplication; follow-on work must not churn that baseline. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
