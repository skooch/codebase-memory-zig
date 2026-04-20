# Plan: Moderate Index Mode Parity

## Goal
Close the released latest-upstream `index_repository.mode=moderate` gap by
adding a real Zig `moderate` mode, tightening the actual `fast`/`moderate`/`full`
pipeline split, and updating the tool-surface fixtures to reflect the new
contract.

## Current Phase
Completed

## File Map
- Modify: `src/pipeline.zig`
- Modify: `src/discover.zig`
- Modify: `src/mcp.zig`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/protocol-contract.json`
- Modify: `testdata/interop/golden/tool-surface-parity.json`
- Create: `docs/plans/in-progress/20-moderate-index-mode-parity-progress.md`

## Phases

### Phase 1: Lock the mode contract
- [x] Re-read the released upstream `moderate` mode description and map it onto
      the current Zig pipeline so the new mode is behaviorally real rather than
      a schema alias.
- [x] Decide the exact Zig meaning of `fast`, `moderate`, and `full`, including
      which discovery and enrichment passes belong to each mode.
- **Status:** completed

### Phase 2: Implement the mode split
- [x] Add `moderate` to the public MCP schema and request parsing.
- [x] Refactor the pipeline so `fast`, `moderate`, and `full` each have explicit
      pass-selection behavior instead of sharing the same enriched path.
- [x] Add focused tests for the public mode contract and at least one concrete
      behavioral difference between `fast` and `moderate`.
- **Status:** completed

### Phase 3: Reclassify the tool surface
- [x] Update the interop manifest and generated goldens so the tool-surface
      fixtures stop encoding the old unsupported-`moderate` error contract.
- [x] Update the parity docs so `index_repository.mode` is no longer listed as
      the active latest-upstream gap after this slice lands.
- [x] Move this plan to `implemented` only after the verification stack is
      green.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --update-golden`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this as a real pipeline-mode slice, not a schema-only surface patch | The current repo already documents the unsupported-`moderate` error as an honest gap; closing it requires actual internal behavior, not just a wider enum. |
| Keep `semantic_query` and `SEMANTICALLY_RELATED` out of scope | Those are still larger semantic-search backlog items; this slice only closes the public indexing-mode contract and the mode split it depends on. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Full compare reopened `protocol-contract` mismatch against the stale local C checkout after Zig started advertising `mode=moderate` | Initial manifest-only tool-surface update left `protocol-contract` snapshotting the full `index_repository` schema, so compare mode treated the widened enum as a strict shared-floor contract | Updated `scripts/run_interop_alignment.sh` so contract fixtures snapshot only the schema fields they explicitly request, then narrowed `protocol-contract` back to the shared floor while keeping `tool-surface-parity` as the latest-upstream diagnostic fixture. |
