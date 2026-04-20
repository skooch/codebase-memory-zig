# Plan: Near-Parity Runtime CLI Packaging

## Goal
Promote or downgrade the runtime, CLI, setup, packaging, and ops rows using
exact harness coverage and explicit scope decisions.

## Current Phase
Pending

## File Map
- Modify: `src/runtime_lifecycle.zig`
- Modify: `src/watcher.zig`
- Modify: `src/cli.zig`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/cli-parity.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`

## Phases

### Phase 1: Decide the packaging and ops target
- [ ] Decide whether release/install packaging full parity includes upstream UI
      artifacts, broader release metadata, signing, and provenance outputs.
- [ ] Decide whether the benchmark/soak/security row is intended to reach full
      parity or should be downgraded because the upstream audit surface is
      intentionally broader.
- **Status:** pending

### Phase 2: Add exact runtime and CLI harness coverage
- [ ] Add end-to-end harness coverage for watcher registration of previously
      indexed projects, idle close/reopen, startup auto-index, startup update
      notice injection timing, and signal-driven shutdown under active stdio.
- [ ] Add temp-home CLI parity cases for update-noop-when-latest, archive
      replacement edge cases, and exact config key round-tripping.
- [ ] Add setup-script and packaged-archive assertions for shell and PowerShell
      entrypoints.
- **Status:** pending

### Phase 3: Fix only the runtime and CLI deltas exposed by exact harnesses
- [ ] Update `src/runtime_lifecycle.zig`, `src/watcher.zig`, and `src/cli.zig`
      where the new exact harnesses reveal real user-visible divergence.
- [ ] Do not broaden packaging beyond the selected scope from Phase 1.
- **Status:** pending

### Phase 4: Reclassify runtime, CLI, and packaging rows
- [ ] Promote rows with exact runtime or CLI parity and exact harness coverage.
- [ ] Downgrade packaging or ops rows that remain intentionally narrower than
      the upstream release surface.
- **Status:** pending

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_cli_parity.sh --zig-only`
- `bash scripts/run_cli_parity.sh`
- `bash scripts/run_interop_alignment.sh --zig-only`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate runtime/CLI from graph work | These rows have different harnesses and different scope decisions. |
| Downgrade packaging rows if the broader upstream release surface is out of scope | The docs should reflect the product we actually ship. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
