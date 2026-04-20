# Progress

## Session: 2026-04-20

### Phase 1: Define the bounded Windows edge matrix
- **Status:** complete
- Actions:
  - Created the Windows runtime edge-coverage plan as backlog item `10`.
  - Narrowed the tranche to Windows sessions where `HOME` is unset but `USERPROFILE`, `HOMEDRIVE` plus `HOMEPATH`, `APPDATA`, and `LOCALAPPDATA` still define the real path roots.
  - Chose three bounded proof points: home-directory fallback, installer/config behavior under Windows env roots without `HOME`, and stdio runtime DB creation plus startup notice behavior under the same env shape.
  - Explicitly deferred broader native Windows process execution, shell, archive, and filesystem oddities that cannot be proven from this environment.
- Files modified:
  - `docs/plans/implemented/10-windows-runtime-edge-coverage-plan.md`
  - `docs/plans/implemented/10-windows-runtime-edge-coverage-progress.md`

### Phase 2: Add Windows edge coverage and fixes
- **Status:** complete
- Actions:
  - Added Windows home-directory fallback helpers in `src/cli.zig` so the CLI and runtime cache path logic now work with `USERPROFILE` or `HOMEDRIVE` plus `HOMEPATH` even when `HOME` is unset.
  - Extended the Zig unit tests to lock the Windows `LOCALAPPDATA` no-`HOME` cache-root path and both `USERPROFILE` and drive-plus-path home fallbacks.
  - Extended `scripts/run_cli_parity.sh` so the Windows lane now drops `HOME`, uses a spaced `USERPROFILE`, and proves `install` plus `config set` still write into the expected `APPDATA` and `LOCALAPPDATA` roots.
  - Added `testdata/runtime/windows-edge-cases/initialize-with-update.jsonl` and extended `scripts/test_runtime_lifecycle.sh` so the runtime harness now proves stdio startup creates the DB under `LOCALAPPDATA` and still carries the one-shot update notice under the same Windows env fallback.
- Files modified:
  - `src/cli.zig`
  - `scripts/run_cli_parity.sh`
  - `scripts/test_runtime_lifecycle.sh`
  - `testdata/runtime/windows-edge-cases/initialize-with-update.jsonl`

### Phase 3: Rebaseline Windows-support claims
- **Status:** complete
- Actions:
  - Promoted the measured Windows no-`HOME` fallback contract in the installer and comparison docs.
  - Narrowed the remaining Windows gap language to host-native process, archive, and shell behavior outside the now-verified env-root contract.
  - Rebased the queue so plan `11` becomes the next execution item after this plan moves to `implemented`.
- Verification:
  - `bash scripts/fetch_grammars.sh --force`
  - `zig build`
  - `zig build test`
  - `bash scripts/test_runtime_lifecycle.sh`
  - `bash scripts/run_cli_parity.sh --update-golden`
  - `bash scripts/run_cli_parity.sh --zig-only`
  - `bash scripts/run_cli_parity.sh`
- Observed results:
  - `bash scripts/test_runtime_lifecycle.sh` now passes the Windows env-fallback case, including runtime DB creation at `LOCALAPPDATA/codebase-memory-zig/codebase-memory-zig.db`.
  - `bash scripts/run_cli_parity.sh --zig-only` now passes `112` checks, including `windows_contract.home_less_install_success` and `windows_contract.config_set_without_home_success`.
  - Full Zig-vs-C CLI parity remains green with `0` mismatches because the shared compare surface is unchanged.
- Files modified:
  - `docs/installer-matrix.md`
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`
  - `docs/plans/implemented/10-windows-runtime-edge-coverage-plan.md`
  - `docs/plans/implemented/10-windows-runtime-edge-coverage-progress.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-20 | `zig build` in the fresh worktree failed on missing vendored grammars such as `vendored/grammars/rust/parser.c` | The worktree had been bootstrapped, but the vendored grammar tree was still incomplete for a full build | Re-ran `bash scripts/fetch_grammars.sh --force`, which is the documented recovery path for this repo's stale vendored-grammar state |
