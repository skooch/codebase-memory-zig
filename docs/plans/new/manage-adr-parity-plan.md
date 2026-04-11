# Plan: Manage ADR Parity

## Goal
Implement the original `manage_adr` capability in the Zig port with persisted ADR storage, MCP/CLI support, and parity-level verification.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/manage-adr-parity-plan.md`
- Create: `docs/plans/new/manage-adr-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/zig-port-plan.md`
- Create: `src/adr.zig`
- Modify: `src/mcp.zig`
- Modify: `src/main.zig`
- Modify: `src/store.zig`
- Modify: `src/store_test.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Create: `testdata/interop/adr-parity/README.md`

## Phases

### Phase 1: Lock the ADR Contract
- [ ] Re-read the original ADR implementation and document the overlapping `manage_adr` verbs, payload shapes, and persistence rules in `docs/gap-analysis.md`.
- [ ] Add the file map, verification commands, and acceptance criteria for the Zig ADR slice to `docs/plans/new/manage-adr-parity-progress.md`.
- [ ] Add a minimal local ADR fixture in `testdata/interop/adr-parity/README.md` so parity checks can run without depending on an external repo.
- **Status:** pending

### Phase 2: Implement ADR Persistence and Tool Wiring
- [ ] Add `src/adr.zig` to own ADR file loading, section updates, and rendered summaries instead of scattering the behavior across `src/mcp.zig`.
- [ ] Extend `src/store.zig`, `src/mcp.zig`, and `src/main.zig` so `manage_adr` is advertised, routed, and persisted through the same MCP and one-shot CLI paths as the original shared tools.
- [ ] Add focused ADR regression coverage in `src/store_test.zig` and any direct `src/mcp.zig` tests needed to lock the supported modes and error handling.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Expand `scripts/run_interop_alignment.sh` with `manage_adr` fixture probes that compare the overlapping create, read, and section-update flows against the original implementation.
- [ ] Re-run `zig build`, `zig build test`, and the ADR-enabled interop harness until the new tool surface is green.
- [ ] Update `docs/port-comparison.md`, `docs/gap-analysis.md`, and `docs/zig-port-plan.md` so the `manage_adr` row and dependent summary rows move from `Deferred` or `Partial` only after evidence exists.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep ADR behavior in `src/adr.zig` instead of embedding it directly in `src/mcp.zig` | File-backed ADR editing is stateful enough to justify its own module and tests. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
