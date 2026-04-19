# Plan: Verification Remediation

## Goal
Restore all required verification paths to an honestly green state, close the currently known interop and snapshot drift on `main`, and tighten the remaining harness and CI gaps called out by the verification audit.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/verification-remediation-plan.md`
- Create: `docs/plans/new/verification-remediation-progress.md`
- Modify: `docs/plans/new/README.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `CLAUDE.md`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/interop-nightly.yml`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/python-parity.json`
- Create: `testdata/interop/golden/discovery-scope.json`
- Create: `testdata/interop/golden/python-framework-cases.json`
- Create: `testdata/interop/golden/typescript-import-cases.json`

## Phases

### Phase 1: Stabilize the current red verification surface
- [ ] Reproduce the current verification state in the execution worktree with `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_cli_parity.sh --zig-only`, and record the exact failing scopes in `docs/plans/in-progress/verification-remediation-progress.md`.
- [ ] Update `testdata/interop/golden/python-parity.json` or the corresponding canonicalization in `scripts/run_interop_alignment.sh` so the `get_graph_schema` contract is intentionally represented and the zig-only comparison no longer fails on schema-shape drift alone.
- [ ] Generate and commit missing zig-only golden snapshots for `discovery-scope`, `python-framework-cases`, and `typescript-import-cases` under `testdata/interop/golden/` so every manifest fixture expected by `bash scripts/run_interop_alignment.sh --zig-only` has a committed baseline.
- [ ] Re-run `bash scripts/run_interop_alignment.sh --zig-only` until the full zig-only interop harness is green on `main`.
- **Status:** pending

### Phase 2: Close the known harness and assertion debt from the audit
- [ ] Update `testdata/interop/manifest.json` so the shared interop fixtures exercise `get_code_snippet`, `get_graph_schema`, `index_status`, and `delete_project` with concrete assertions rather than tool-list presence only.
- [ ] Tighten weak manifest assertions in `testdata/interop/manifest.json`, including non-vacuous `detect_changes` checks and `required_rows_min` on parity queries that are supposed to return rows.
- [ ] Update `scripts/run_interop_alignment.sh` so snapshot comparison and report output remain stable and actionable after the added assertions, including any needed schema canonicalization or diff-detail improvements discovered while fixing the current red paths.
- [ ] Refresh `docs/interop-testing-review.md` so it no longer reports already-resolved items as open and clearly distinguishes remaining verification debt from issues closed by this execution slice.
- **Status:** pending

### Phase 3: Align CI gates, documentation, and full verification
- [ ] Decide and implement the intended CI posture in `.github/workflows/ci.yml` and `.github/workflows/interop-nightly.yml` so required gates match the repo's actual verification contract, including whether full Zig-vs-C comparison remains nightly-only or gains stronger surfacing.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the verification posture reflects the post-remediation state instead of the current drift snapshot.
- [ ] Re-run the required verification set: `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, `bash scripts/run_cli_parity.sh --zig-only`, and the current ops suite entrypoints from `.github/workflows/ops-checks.yml`; also run the full Zig-vs-C comparison locally if the adjacent C reference checkout is available.
- [ ] If any undocumented verification failure mode appears during execution, add the recovery rule to `CLAUDE.md` before continuing.
- [x] Move the plan and progress files from `docs/plans/new/` to `docs/plans/in-progress/` before implementation starts, and only move them to `docs/plans/implemented/` after the required verification set is green or any remaining blocker is documented concretely.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat the work as a single verification-remediation plan instead of separate doc and harness plans | The current red interop state, audit findings, fixture debt, and CI posture are coupled parts of one verification contract. |
| Require both zig-only and, when locally available, Zig-vs-C verification evidence before closure | The repo already relies on both golden snapshots and the C reference for confidence; resolving verification debt should not narrow that contract. |
| Keep documentation updates inside the same plan as harness fixes | The current docs already drifted from the actual verification state on `main`, so documentation must close in the same execution slice as the technical fixes. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
