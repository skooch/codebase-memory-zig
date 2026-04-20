# Progress: Near-Parity Runtime CLI Packaging

## 2026-04-21

- Moved the final runtime/CLI/packaging slice into active execution and
  re-audited which rows still had evidence gaps versus which rows only had
  scope drift against latest upstream.
- Confirmed that the existing runtime and CLI harnesses already covered most of
  the plan surface before any new code changes:
  - `scripts/test_runtime_lifecycle.sh` already proved EOF shutdown, live
    `SIGTERM`, one-shot update-notice timing, `notifications/initialized`
    silence, and Windows no-`HOME` runtime cache-root fallback.
  - `scripts/test_runtime_lifecycle_extras.sh` already proved idle runtime DB
    close and reopen under a live stdio session.
  - `scripts/run_cli_parity.sh --zig-only` already proved `112` exact CLI and
    productization checks across shared flows, detected-scope installers,
    Windows layout, operational controls, and local packaged self-update.
  - `scripts/run_cli_parity.sh` already full-compared the overlapping shared
    Codex/Claude CLI contract with `18` checks and `0` mismatches.
- The only real missing runtime evidence was startup-path coverage in
  `src/main.zig`, not a missing runtime feature.
- Refactored startup auto-index into a testable helper,
  `maybeAutoIndexOnStartupResolved`, without changing the user-visible startup
  behavior.
- Added direct startup tests in `src/main.zig` for:
  - persisted-project watcher registration via `registerIndexedProjects`
  - startup auto-index of the current temp repo plus watcher registration
- Kept the packaging and ops scope honest instead of widening implementation:
  - release/install packaging is now documented as `Partial`, because the Zig
    repo intentionally omits the broader latest-upstream UI, signing,
    attestation, and provenance surface
  - the benchmark/soak/security rows are now documented as `Partial`, because
    the local bounded suite still stops short of the original's broader audit,
    fuzz, and long-duration soak layers
- Strengthened the runtime and verification docs to reflect the measured state:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
- Closed the ordering program as well, because all four subsystem parity plans
  now have final outcomes and the comparison docs reflect the measured end
  state.
- Final verification for this plan:
  - `zig fmt src/main.zig`: pass
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/test_runtime_lifecycle.sh`: pass
  - `bash scripts/test_runtime_lifecycle_extras.sh`: pass
  - `bash scripts/run_cli_parity.sh --zig-only`: pass (`112` exact checks)
  - `bash scripts/run_cli_parity.sh`: pass (`18` shared checks, `0`
    mismatches)
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`39/39`)
