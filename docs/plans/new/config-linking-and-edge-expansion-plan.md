# Plan: Config Linking And Edge Expansion

## Goal
Expand the Zig graph beyond the completed shared `CONFIGURES`, `WRITES`, and `USES_TYPE` slice into the original's broader config-linking and long-tail edge vocabulary.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/config-linking-and-edge-expansion-plan.md`
- Create: `docs/plans/new/config-linking-and-edge-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/cypher.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Create: `testdata/interop/config-linking/app.yaml`
- Create: `testdata/interop/config-linking/main.py`

## Phases

### Phase 1: Lock the Long-Tail Edge Contract
- [ ] Re-read the original config-linking and richer-edge passes and capture the still-missing edge families in `docs/gap-analysis.md`.
- [ ] Add local config and code fixtures in `testdata/interop/config-linking/` that exercise the next unported config-link and edge cases.
- [ ] Record the targeted Cypher queries and verification commands in `docs/plans/new/config-linking-and-edge-expansion-progress.md`.
- **Status:** pending

### Phase 2: Implement Broader Edge Extraction
- [ ] Extend `src/extractor.zig`, `src/pipeline.zig`, `src/store.zig`, `src/graph_buffer.zig`, and `src/cypher.zig` so the next tranche of config-link and long-tail edges is persisted and queryable.
- [ ] Add focused regression coverage for edge deduplication, config-key normalization, and any new edge labels introduced in the tranche.
- [ ] Update `scripts/run_interop_alignment.sh` so the new edge families are compared explicitly against the original instead of being left diagnostic-only.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and the expanded interop harness until the newly targeted edge rows are stable.
- [ ] Update `docs/port-comparison.md` so the richer-edge rows move only as far as the new explicit evidence justifies.
- [ ] Record the remaining long-tail edge backlog after the completed tranche in `docs/plans/new/config-linking-and-edge-expansion-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan separate from the completed shared parity plan | The shared overlap is already closed, and the remaining long-tail edge work needs its own acceptance boundary. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
