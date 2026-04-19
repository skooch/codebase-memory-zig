# Plan: Windows Runtime Edge Coverage

## Goal
Add bounded but explicit Windows-native runtime and filesystem edge coverage so the docs can claim the current Windows support level more confidently.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/10-windows-runtime-edge-coverage-plan.md`
- Create: `docs/plans/new/10-windows-runtime-edge-coverage-progress.md`
- Modify: `docs/installer-matrix.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `src/runtime_lifecycle.zig`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `scripts/test_runtime_lifecycle.sh`
- Modify: `testdata/agent-comparison/windows-paths/`
- Create: `testdata/runtime/windows-edge-cases/`

## Phases

### Phase 1: Define the bounded Windows edge matrix
- [ ] Enumerate the remaining Windows-native gaps the docs still call out, such as path normalization, cache-root creation, startup lifecycle, and filesystem oddities.
- [ ] Select a bounded set of Windows edge cases that can be exercised without inventing unsupported runtime claims.
- [ ] Record the chosen Windows edge matrix and excluded cases in `docs/plans/in-progress/10-windows-runtime-edge-coverage-progress.md`.
- **Status:** pending

### Phase 2: Add Windows edge coverage and fixes
- [ ] Extend `src/cli.zig`, `src/main.zig`, and `src/runtime_lifecycle.zig` only where the selected Windows edge cases expose real behavior gaps.
- [ ] Add or extend the parity and runtime harnesses plus Windows-oriented fixtures so each selected case has executable coverage.
- [ ] Refresh any affected fixture outputs only after the chosen Windows edge matrix is green locally.
- **Status:** pending

### Phase 3: Rebaseline Windows-support claims
- [ ] Re-run the relevant CLI parity and runtime verification commands for the chosen Windows edge matrix.
- [ ] Update `docs/installer-matrix.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so the Windows-support language reflects the new measured coverage.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the documented Windows edge coverage is backed by the harness.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this as bounded Windows edge coverage, not full Windows parity | The current docs already distinguish strong path coverage from exhaustive native runtime parity. |
| Use only cases that can be verified in-repo | This plan should not depend on aspirational platform claims. |
| Keep runtime and installer edges together only where they share the same fixture evidence | The goal is clearer Windows support statements, not a mixed umbrella plan. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
