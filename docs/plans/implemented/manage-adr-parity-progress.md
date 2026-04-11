# Progress

## Session: 2026-04-11

### Phase 1: Lock the ADR Contract
- **Status:** completed
- Actions:
  - Moved `docs/plans/new/manage-adr-parity-plan.md` to `docs/plans/in-progress/manage-adr-parity-plan.md` before implementation, following the repo's plan convention.
  - Re-read the current Zig MCP/store surface alongside the original `manage_adr` implementation to confirm the overlapping tool contract is `get`, `update`, and `sections`, with project-scoped persistence and a no-ADR hint path.
  - Confirmed that the Zig repo already reserves the `manage_adr` tool enum entry but does not advertise or dispatch it yet, which keeps the implementation slice bounded to store persistence, MCP wiring, tests, and doc reclassification.
- Files modified:
  - `docs/plans/implemented/manage-adr-parity-plan.md`
  - `docs/plans/implemented/manage-adr-parity-progress.md`

### Phase 2: Implement ADR Persistence and Tool Wiring
- **Status:** completed
- Actions:
  - Added `src/adr.zig` as the shared home for ADR markdown section extraction instead of embedding that parsing into `src/mcp.zig`.
  - Extended `src/store.zig` with `project_summaries` persistence plus `upsertAdr`, `getAdr`, `deleteAdr`, and `freeAdr`, keeping ADR data tied to the indexed project lifecycle.
  - Extended `src/mcp.zig` so `manage_adr` is now advertised by `tools/list`, routed through tool dispatch, and supports the overlapping `get`, `update`, and `sections` modes.
  - Added direct regression coverage in `src/store.zig` and `src/mcp.zig` for ADR round-tripping, tool advertisement, and `update` / `get` / `sections` behavior.
- Files modified:
  - `src/adr.zig`
  - `src/mcp.zig`
  - `src/root.zig`
  - `src/store.zig`

### Phase 3: Verify and Reclassify
- **Status:** completed
- Actions:
  - Added a local ADR parity fixture in `testdata/interop/adr-parity/` with both `README.md` context and an indexable `main.py` so the interop harness can verify `manage_adr` without depending on an external repo.
  - Expanded `scripts/run_interop_alignment.sh` and `testdata/interop/manifest.json` so the harness now verifies shared `manage_adr` update, get, and sections flows against the original implementation.
  - Normalized the ADR parity comparison to compare semantic content and discovered headings rather than raw escaped newline storage, matching the shared user-visible behavior across Zig and C.
  - Re-ran the required verification:
    - `zig build` → passed
    - `zig build test` → passed
    - `bash scripts/run_interop_alignment.sh` → passed with `Mismatches: 0`
  - Updated `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` so the repo now treats `manage_adr` as implemented while leaving unrelated deferred systems untouched.
- Files modified:
  - `docs/gap-analysis.md`
  - `docs/port-comparison.md`
  - `docs/zig-port-plan.md`
  - `scripts/run_interop_alignment.sh`
  - `testdata/interop/adr-parity/README.md`
  - `testdata/interop/adr-parity/main.py`
  - `testdata/interop/manifest.json`
