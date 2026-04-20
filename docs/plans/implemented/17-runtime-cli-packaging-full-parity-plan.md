# Plan: Near-Parity Runtime CLI Packaging

## Goal
Promote or downgrade the runtime, CLI, setup, packaging, and ops rows using
exact harness coverage and explicit scope decisions.

## Current Phase
Completed

## File Map
- Modify: `src/main.zig`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`
- Create: `docs/plans/implemented/17-runtime-cli-packaging-full-parity-progress.md`

## Phases

### Phase 1: Decide the packaging and ops target
- [x] Decide whether release/install packaging full parity includes upstream UI
      artifacts, broader release metadata, signing, and provenance outputs.
- [x] Decide whether the benchmark/soak/security row is intended to reach full
      parity or should be downgraded because the upstream audit surface is
      intentionally broader.
- **Status:** completed

### Phase 2: Add exact runtime and CLI harness coverage
- [x] Add end-to-end harness coverage for watcher registration of previously
      indexed projects, idle close/reopen, startup auto-index, startup update
      notice injection timing, and signal-driven shutdown under active stdio.
- [x] Add temp-home CLI parity cases for update-noop-when-latest, archive
      replacement edge cases, and exact config key round-tripping.
- [x] Add setup-script and packaged-archive assertions for shell and PowerShell
      entrypoints.
- **Status:** completed

### Phase 3: Fix only the runtime and CLI deltas exposed by exact harnesses
- [x] Update only the runtime or CLI code paths where the exact harnesses
      reveal real user-visible divergence.
- [x] Do not broaden packaging beyond the selected scope from Phase 1.
- **Status:** completed

### Phase 4: Reclassify runtime, CLI, and packaging rows
- [x] Promote rows with exact runtime or CLI parity and exact harness coverage.
- [x] Downgrade packaging or ops rows that remain intentionally narrower than
      the upstream release surface.
- **Status:** completed

## Verification
- `zig fmt src/main.zig`
- `zig build`
- `zig build test`
- `bash scripts/test_runtime_lifecycle.sh`
- `bash scripts/test_runtime_lifecycle_extras.sh`
- `bash scripts/run_cli_parity.sh --zig-only`
- `bash scripts/run_cli_parity.sh`
- `bash scripts/run_interop_alignment.sh --zig-only`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate runtime/CLI from graph work | These rows have different harnesses and different scope decisions. |
| Downgrade packaging rows if the broader upstream release surface is out of scope | The docs should reflect the product we actually ship. |
| Treat existing CLI parity coverage as sufficient when it is already exact and green | The current CLI harness already proves `112` exact zig-only checks plus a clean shared C compare, so duplicating it would add noise instead of confidence. |
| Add direct startup tests instead of inventing a second runtime harness | The missing evidence was startup watcher registration and startup auto-index, which are better pinned with focused `src/main.zig` tests than with a broader shell wrapper. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
