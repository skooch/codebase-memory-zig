# Plan: Ops Scripts Parity

## Goal
Broaden the Zig repo's operational tooling so benchmarking, soak testing, and security or audit checks reach the script surface the original ships.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ops-scripts-parity-plan.md`
- Create: `docs/plans/new/ops-scripts-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `scripts/run_benchmark_suite.sh`
- Create: `scripts/run_soak_suite.sh`
- Create: `scripts/run_security_audit.sh`
- Create: `docs/ops-tooling.md`
- Create: `.github/workflows/ops-tooling.yml`

## Phases

### Phase 1: Lock the Ops Tooling Contract
- [ ] Re-read the original benchmark, soak, and security script surface and capture the overlapping lanes in `docs/gap-analysis.md`.
- [ ] Define the supported Zig ops-tooling lanes, fixtures, and verification commands in `docs/plans/new/ops-scripts-parity-progress.md`.
- [ ] Keep the scope explicitly limited to scriptable repo tooling and out of the runtime or packaging plans.
- **Status:** pending

### Phase 2: Implement Soak And Security Lanes
- [ ] Extend `scripts/run_benchmark_suite.sh` and add `scripts/run_soak_suite.sh` plus `scripts/run_security_audit.sh` so the repo has dedicated entrypoints for each ops lane.
- [ ] Add `.github/workflows/ops-tooling.yml` so the new tooling can run in CI instead of existing only as local commands.
- [ ] Add `docs/ops-tooling.md` to describe the purpose, inputs, and outputs of each script lane.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run the benchmark, soak, and security scripts successfully on local fixtures and record the outputs in `docs/plans/new/ops-scripts-parity-progress.md`.
- [ ] Update `docs/port-comparison.md` so the ops-script rows move out of `Partial` or `Deferred` only after the new tooling is runnable.
- [ ] Record any intentionally skipped original scripts in `docs/plans/new/ops-scripts-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep ops tooling separate from core feature parity | Benchmark, soak, and audit scripts are repo-operability work rather than core graph-engine behavior. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
