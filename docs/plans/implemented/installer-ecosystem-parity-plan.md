# Plan: Installer Ecosystem Parity

## Goal
Expand the Zig installer from shared Codex/Claude parity into the original's broader multi-agent ecosystem, including instructions, skills, hooks, and reminder setup.

## Current Phase
Complete

## File Map
- Modify: `docs/plans/in-progress/installer-ecosystem-parity-plan.md`
- Create: `docs/plans/in-progress/installer-ecosystem-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/installer-matrix.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `scripts/run_cli_parity.sh`
- Create: `testdata/cli-agent-fixtures/codex/config.toml`
- Create: `testdata/cli-agent-fixtures/claude/.mcp.json`
- Create: `testdata/cli-agent-fixtures/gemini/settings.json`
- Create: `testdata/cli-agent-fixtures/opencode/opencode.json`
- Create: `testdata/cli-agent-fixtures/openclaw/openclaw.json`

## Phases

### Phase 1: Lock the Installer Matrix
- [x] Re-read the original installer surface and document the full agent-target, instruction-file, hook, and reminder matrix in `docs/gap-analysis.md`.
- [x] Add local config fixtures for the next agent targets in `testdata/cli-agent-fixtures/` so installer work can be verified without touching live config.
- [x] Record the rollout order, out-of-scope targets, and verification commands in `docs/plans/in-progress/installer-ecosystem-parity-progress.md`.
- **Status:** completed

### Phase 2: Implement Broader Agent Support
- [x] Extend `src/main.zig` install reporting so the broader detected-agent matrix is visible instead of only the shared shipped pair.
- [x] Keep `src/cli.zig` aligned with the original multi-agent file layout where the broader matrix is already implemented, and only change code when the new harness exposes a real mismatch.
- [x] Update `scripts/run_cli_parity.sh` so broader installer targets and auxiliary file effects are checked in temp homes against fixture-seeded state.
- **Status:** completed

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and the expanded CLI parity harness until the broader installer matrix is stable.
- [x] Add `docs/installer-matrix.md` and update `docs/port-comparison.md` so the remaining CLI-productization rows move only after the new targets are proven.
- [x] Record any still-unsupported agents or installer side effects in `docs/plans/in-progress/installer-ecosystem-parity-progress.md`.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate agent-matrix work from release packaging | Users need a clear distinction between how the binary is distributed and what post-install config it can manage. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
