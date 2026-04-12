# Plan: Agent Ecosystem Installation

## Goal
Match the original's post-install agent onboarding story by expanding the Zig installer to configure the shared agent ecosystem expectations around instructions, skills, and hooks or reminders.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/02-agent-ecosystem-installation-plan.md`
- Create: `docs/plans/new/ready-to-go/02-agent-ecosystem-installation-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `src/config.zig`
- Create: `assets/agents/`
- Create: `docs/agent-install.md`
- Create: `scripts/test_agent_installation.sh`

## Phases

### Phase 1: Lock the Agent Installation Contract
- [ ] Re-read the original installer behavior for agent instructions, skills, and reminders or hooks and capture the shared contract in `docs/gap-analysis.md`.
- [ ] Define the supported shared agent targets, filesystem effects, and verification workflow in `docs/plans/new/ready-to-go/02-agent-ecosystem-installation-progress.md`.
- [ ] Separate this scope from packaging and release artifacts so the plan focuses only on post-install agent setup behavior.
- **Status:** pending

### Phase 2: Implement Agent Setup Assets
- [ ] Extend `src/cli.zig`, `src/main.zig`, and `src/config.zig` so install and update flows can materialize shared instruction, skill, and reminder assets for the supported agents.
- [ ] Add repo-owned templates or fixtures under `assets/agents/` so the installer writes deterministic agent-facing files instead of embedding large ad hoc strings.
- [ ] Add `docs/agent-install.md` and `scripts/test_agent_installation.sh` so the shared agent setup flow is documented and repeatably testable in temp home directories.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and `bash scripts/test_agent_installation.sh` until the supported agent setup flow is reproducible and reversible in temp home directories.
- [ ] Update `docs/port-comparison.md` so the agent-installation row moves out of `Deferred` only after the installer proves the shared instruction, skill, and reminder behavior.
- [ ] Record the final verification transcript and any intentionally unsupported agent-specific extras in `docs/plans/new/ready-to-go/02-agent-ecosystem-installation-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep the first pass to shared agent behaviors | The drop-in replacement claim depends on matching the overlapping ecosystem setup, not immediately reproducing every original-only agent target. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
