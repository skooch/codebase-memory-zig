# Plan: Installer Productization Parity

## Goal
Close the highest-value installer and productization gaps still called out by the comparison docs without reopening already-green shared CLI parity slices.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/09-installer-productization-parity-plan.md`
- Create: `docs/plans/new/09-installer-productization-parity-progress.md`
- Modify: `docs/installer-matrix.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `install.sh`
- Modify: `install.ps1`
- Modify: `scripts/setup.sh`
- Modify: `scripts/setup-windows.ps1`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `testdata/agent-comparison/`

## Phases

### Phase 1: Choose the next installer gap tranche
- [ ] Break the documented installer/productization gaps into concrete slices, including binary self-replacement, Claude layout parity, shipped-vs-detected defaults, and release-facing setup polish.
- [ ] Select the next highest-leverage tranche that can be verified cleanly in the temp-home harness.
- [ ] Record the chosen installer tranche and explicit deferrals in `docs/plans/in-progress/09-installer-productization-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement and verify the selected installer slice
- [ ] Extend `src/cli.zig`, `src/main.zig`, and any required shell or PowerShell entrypoints for the chosen installer/productization behavior.
- [ ] Update `scripts/run_cli_parity.sh` and the agent-comparison fixtures so the selected slice is exercised in the public parity harness.
- [ ] Refresh only the affected installer evidence after the selected tranche is green in local verification.
- **Status:** pending

### Phase 3: Rebaseline installer docs
- [ ] Re-run the CLI parity verification needed for the chosen installer tranche.
- [ ] Update `docs/installer-matrix.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so the remaining installer debt is described from the new measured baseline.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the chosen productization slice is fully verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep this plan scoped to one installer tranche at a time | The remaining productization surface is too broad for one safe pass. |
| Require temp-home harness evidence for every promoted claim | Installer parity is easy to overstate without side-effect verification. |
| Preserve already-green Codex/Claude shared parity as a hard floor | The plan should only add coverage, not trade away the current shared baseline. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
