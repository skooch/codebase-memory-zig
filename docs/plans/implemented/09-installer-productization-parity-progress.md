# Progress

## Session: 2026-04-20

### Phase 1: Choose the next installer gap tranche
- **Status:** complete
- Actions:
  - Created the installer/productization parity plan as backlog item `09`.
  - Broke the remaining installer debt into binary self-replacement, shipped-vs-detected defaults, Claude layout parity, and broader release-facing trust or packaging polish.
  - Chose bounded binary self-replacement through configured `download_url` plus packaged local release fixtures as the highest-leverage tranche that could be verified end to end in the temp-home harness.
  - Explicitly deferred Windows-native self-replacement behavior, broader network-backed updater policy, and the original multi-skill Claude layout.
- Files modified:
  - `docs/plans/implemented/09-installer-productization-parity-plan.md`
  - `docs/plans/implemented/09-installer-productization-parity-progress.md`

### Phase 2: Implement and verify the selected installer slice
- **Status:** complete
- Actions:
  - Added host-artifact selection, release-root resolution, checksum verification, tarball extraction, and atomic binary replacement helpers in `src/cli.zig`.
  - Wired `update` in `src/main.zig` so configured `download_url` now drives a real packaged-archive self-replacement path, with dry-run reporting and bounded failure handling.
  - Extended `scripts/run_cli_parity.sh` with a zig-only `productization_contract` lane that builds a local packaged release fixture, seeds a temp HOME install, verifies dry-run stability, performs the real update, and confirms both binary replacement and agent-config refresh.
  - Refreshed `testdata/interop/golden/cli-parity.json` so the new productization assertions are locked into the public zig-only CLI baseline.
- Files modified:
  - `src/cli.zig`
  - `src/main.zig`
  - `scripts/run_cli_parity.sh`
  - `testdata/interop/golden/cli-parity.json`

### Phase 3: Rebaseline installer docs
- **Status:** complete
- Actions:
  - Updated the installer and comparison docs to promote the bounded file-backed self-update contract and narrow the remaining installer debt to shipped-scope defaults, consolidated Claude packaging, Windows-native execution gaps, and broader network or trust policy.
  - Rebased the backlog index so this plan can move to `implemented` and the next queued item becomes the Windows runtime-edge coverage plan.
  - Verified the completed installer tranche end to end before archival.
- Verification:
  - `zig build`
  - `zig build test`
  - `bash scripts/run_cli_parity.sh --update-golden`
  - `bash scripts/run_cli_parity.sh --zig-only`
  - `bash scripts/run_cli_parity.sh`
- Observed results:
  - `bash scripts/run_cli_parity.sh --zig-only` now passes `110` checks, including the new `productization_contract` assertions for dry-run stability, packaged-archive replacement, version change, and Codex or Claude config refresh.
  - Full Zig-vs-C CLI parity remains green with `0` mismatches because the shared compare surface is unchanged.
  - The promoted contract is intentionally bounded to configured file-backed packaged archives on supported Unix and macOS hosts.
- Files modified:
  - `docs/installer-matrix.md`
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`
  - `docs/plans/implemented/09-installer-productization-parity-plan.md`
  - `docs/plans/implemented/09-installer-productization-parity-progress.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-20 | `std.fmt.fmtSliceHexLower` not available in Zig 0.15.2 | Initial checksum-formatting implementation in `src/cli.zig` used the missing helper | Switched to `std.fmt.bytesToHex(..., .lower)` and kept the checksum verification path portable to the repo's pinned Zig toolchain |
| 2026-04-20 | `std.tar.Iterator.streamRemaining` expected a `std.Io.Writer`-compatible destination | Initial tar extraction path tried to stream directly into an `ArrayList` writer | Replaced it with a bounded `std.Io.Reader.readAlloc` path over a limited decompressor view so the packaged-binary extraction works under Zig 0.15.2 |
