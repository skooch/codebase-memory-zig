# Plan: Installer Ecosystem Parity

## Goal
Expand the Zig installer from shared Codex/Claude parity into the original's broader multi-agent ecosystem, including instructions, skills, hooks, and reminder setup.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/installer-ecosystem-parity-plan.md`
- Create: `docs/plans/new/installer-ecosystem-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Create: `src/agent_targets.zig`
- Modify: `scripts/run_cli_parity.sh`
- Create: `docs/installer-matrix.md`
- Create: `testdata/cli-agent-fixtures/claude/settings.json`
- Create: `testdata/cli-agent-fixtures/cursor/settings.json`

## Phases

### Phase 1: Lock the Installer Matrix
- [ ] Re-read the original installer surface and document the full agent-target, instruction-file, hook, and reminder matrix in `docs/gap-analysis.md`.
- [ ] Add local config fixtures for the next agent targets in `testdata/cli-agent-fixtures/` so installer work can be verified without touching live config.
- [ ] Record the rollout order, out-of-scope targets, and verification commands in `docs/plans/new/installer-ecosystem-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement Broader Agent Support
- [ ] Add `src/agent_targets.zig` to own target metadata, config-path discovery, and auxiliary file installation for the broader agent matrix.
- [ ] Extend `src/cli.zig` and `src/main.zig` so install, uninstall, and update cover the next supported agents plus instruction, skill, hook, and reminder setup where the original does.
- [ ] Update `scripts/run_cli_parity.sh` so the new shared installer targets and auxiliary file effects are checked in temp homes.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and the expanded CLI parity harness until the broader installer matrix is stable.
- [ ] Add `docs/installer-matrix.md` and update `docs/port-comparison.md` so the remaining CLI-productization rows move only after the new targets are proven.
- [ ] Record any still-unsupported agents or installer side effects in `docs/plans/new/installer-ecosystem-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate agent-matrix work from release packaging | Users need a clear distinction between how the binary is distributed and what post-install config it can manage. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
