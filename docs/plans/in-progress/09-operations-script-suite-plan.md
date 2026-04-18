# Plan: Operations Script Suite

## Goal
Round out the drop-in replacement story by restoring the broader operational scripts around benchmarking, soak runs, and security or audit checks that make the original look production-ready.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/in-progress/09-operations-script-suite-plan.md`
- Create: `docs/plans/in-progress/09-operations-script-suite-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `scripts/run_benchmark_suite.sh`
- Create: `scripts/run_soak_suite.sh`
- Create: `scripts/run_security_audit.sh`
- Create: `docs/operations.md`
- Create: `.github/workflows/ops-checks.yml`

## Phases

### Phase 1: Lock the Operations Contract
- [ ] Re-read the original benchmark, soak, and security script surface and capture the overlapping operational expectations in `docs/gap-analysis.md`.
- [ ] Define the exact operational script entrypoints, CI hooks, and verification workflow in `docs/plans/in-progress/09-operations-script-suite-progress.md`.
- [ ] Keep the scope limited to reproducible repo-owned scripts rather than broadening into unrelated release engineering work.
- **Status:** pending

### Phase 2: Implement Operational Scripts
- [ ] Extend `scripts/run_benchmark_suite.sh` and add `scripts/run_soak_suite.sh` plus `scripts/run_security_audit.sh` so the repo exposes a broader operations surface comparable to the original.
- [ ] Add `.github/workflows/ops-checks.yml` so the operational scripts are exercised in CI instead of existing only as local documentation.
- [ ] Add `docs/operations.md` so the benchmark, soak, and audit entrypoints are documented for maintainers and evaluators.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run the benchmark, soak, and security script entrypoints until each completes successfully in a clean repo environment.
- [ ] Update `docs/port-comparison.md` so the operations-script rows move out of `Partial` or `Deferred` only after the scripts and CI hooks are proven.
- [ ] Record the final verification transcript and any intentionally unsupported operational checks in `docs/plans/in-progress/09-operations-script-suite-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Put operational credibility last in the ready-to-go order | These scripts help the replacement story, but users judge packaging, setup, and core behavior gaps first. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
