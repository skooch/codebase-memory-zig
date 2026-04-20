# Plan: Installer Productization Parity

## Goal
Close the highest-value installer and productization gaps still called out by the comparison docs without reopening already-green shared CLI parity slices.

## Current Phase
Complete

## File Map
- Modify: `docs/installer-matrix.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/README.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `testdata/interop/golden/cli-parity.json`
- Move: `docs/plans/in-progress/09-installer-productization-parity-plan.md` -> `docs/plans/implemented/09-installer-productization-parity-plan.md`
- Move: `docs/plans/in-progress/09-installer-productization-parity-progress.md` -> `docs/plans/implemented/09-installer-productization-parity-progress.md`

## Phases

### Phase 1: Choose the next installer gap tranche
- [x] Break the documented installer/productization gaps into concrete slices, including binary self-replacement, Claude layout parity, shipped-vs-detected defaults, and release-facing setup polish.
- [x] Select the next highest-leverage tranche that can be verified cleanly in the temp-home harness.
- [x] Record the chosen installer tranche and explicit deferrals in the paired progress log.
- **Status:** complete

### Phase 2: Implement and verify the selected installer slice
- [x] Extend `src/cli.zig`, `src/main.zig`, and any required shell or PowerShell entrypoints for the chosen installer/productization behavior.
- [x] Update `scripts/run_cli_parity.sh` and the agent-comparison fixtures so the selected slice is exercised in the public parity harness.
- [x] Refresh only the affected installer evidence after the selected tranche is green in local verification.
- **Status:** complete

### Phase 3: Rebaseline installer docs
- [x] Re-run the CLI parity verification needed for the chosen installer tranche.
- [x] Update `docs/installer-matrix.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so the remaining installer debt is described from the new measured baseline.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the chosen productization slice is fully verified.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan scoped to one installer tranche at a time | The remaining productization surface is too broad for one safe pass. |
| Require temp-home harness evidence for every promoted claim | Installer parity is easy to overstate without side-effect verification. |
| Preserve already-green Codex/Claude shared parity as a hard floor | The plan should only add coverage, not trade away the current shared baseline. |
| Select bounded binary self-replacement as the plan tranche | It closes the highest-value documented installer gap without reopening broader release-trust or multi-skill packaging work. |
| Limit the promoted contract to configured file-backed packaged archives on supported Unix and macOS hosts | That path is fully reproducible in the temp-home harness and does not overclaim Windows-native or network-backed updater behavior. |
| Leave the shipped default scope and consolidated Claude skill layout unchanged | Those are still real productization differences, but they are independent of the chosen self-update slice. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
