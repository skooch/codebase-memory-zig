# Plan: Windows Runtime Edge Coverage

## Goal
Add bounded but explicit Windows-native runtime and filesystem edge coverage so the docs can claim the current Windows support level more confidently.

## Current Phase
Complete

## File Map
- Modify: `docs/installer-matrix.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/README.md`
- Modify: `src/cli.zig`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `scripts/test_runtime_lifecycle.sh`
- Modify: `testdata/interop/golden/cli-parity.json`
- Create: `testdata/runtime/windows-edge-cases/initialize-with-update.jsonl`
- Move: `docs/plans/in-progress/10-windows-runtime-edge-coverage-plan.md` -> `docs/plans/implemented/10-windows-runtime-edge-coverage-plan.md`
- Move: `docs/plans/in-progress/10-windows-runtime-edge-coverage-progress.md` -> `docs/plans/implemented/10-windows-runtime-edge-coverage-progress.md`

## Phases

### Phase 1: Define the bounded Windows edge matrix
- [x] Enumerate the remaining Windows-native gaps the docs still call out, such as path normalization, cache-root creation, startup lifecycle, and filesystem oddities.
- [x] Select a bounded set of Windows edge cases that can be exercised without inventing unsupported runtime claims.
- [x] Record the chosen Windows edge matrix and excluded cases in the paired progress log.
- **Status:** complete

### Phase 2: Add Windows edge coverage and fixes
- [x] Extend the path-resolution substrate only where the selected Windows edge cases expose real behavior gaps.
- [x] Add or extend the parity and runtime harnesses plus Windows-oriented fixtures so each selected case has executable coverage.
- [x] Refresh any affected fixture outputs only after the chosen Windows edge matrix is green locally.
- **Status:** complete

### Phase 3: Rebaseline Windows-support claims
- [x] Re-run the relevant CLI parity and runtime verification commands for the chosen Windows edge matrix.
- [x] Update `docs/installer-matrix.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so the Windows-support language reflects the new measured coverage.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the documented Windows edge coverage is backed by the harness.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat this as bounded Windows edge coverage, not full Windows parity | The current docs already distinguish strong path coverage from exhaustive native runtime parity. |
| Use only cases that can be verified in-repo | This plan should not depend on aspirational platform claims. |
| Keep runtime and installer edges together only where they share the same fixture evidence | The goal is clearer Windows support statements, not a mixed umbrella plan. |
| Choose `HOME`-less Windows env fallback as the tranche | It exposed a real path-resolution gap that affected both installer commands and runtime cache placement without requiring unsupported native Windows execution claims. |
| Prove the runtime side through `LOCALAPPDATA` DB creation plus startup notice behavior | That gives the docs a bounded runtime claim instead of only install-path coverage. |
| Leave broader native Windows archive and process behavior deferred | The repo can verify path-root and startup contracts in-repo, but not full host-native Windows execution semantics from this environment. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
