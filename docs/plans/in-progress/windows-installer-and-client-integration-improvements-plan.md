# Plan: Windows, Installer, and Client Integration Improvements

## Goal
Make the Zig port predictable across Windows paths, agent config discovery, shell behaviors, and MCP client startup sequences, using the upstream support load as the acceptance contract.

## Research Basis

Upstream issue families captured in this plan:
- Windows build, path, and shell failures: `#1`, `#20`, `#80`, `#133`, `#137`, `#138`, `#140`, `#196`, `#227`
- Installer and updater failures: `#17`, `#114`, `#145`, `#158`, `#159`, `#182`, `#221`, `#222`
- Editor and agent integration failures: `#15`, `#19`, `#24`, `#30`, `#77`, `#78`, `#83`, `#129`
- Runtime integration friction and hooks: `#185`, `#188`, `#214`
- Packaging trust and execution friction: `#89`, `#135`, `#230`

Upstream PRs that show the likely implementation shape:
- Windows path and binary-location fixes: `#21`, `#88`, `#146`, `#153`, `#157`, `#160`, `#161`
- Installer matrix expansion: `#36`, `#53`, `#63`, `#64`, `#74`, `#134`, `#174`
- Client handshake and protocol compatibility: `#75`, `#79`, `#101`
- Shell and archive compatibility: `#16`, `#18`, `#198`

Observed upstream pattern:
- Many “the tool is broken” reports were actually config discovery, path normalization, or handshake framing mismatches rather than core graph failures.
- The upstream project reduced support churn when it codified client-specific config shapes and path rules in temp-home tests instead of treating them as ad hoc installer branches.

## Current Phase
Phase 2

## File Map
- Modify: `docs/plans/in-progress/windows-installer-and-client-integration-improvements-plan.md`
- Create: `docs/plans/in-progress/windows-installer-and-client-integration-improvements-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Modify: `src/runtime_lifecycle.zig`
- Modify: `src/discover.zig`
- Modify: `scripts/run_cli_parity.sh`
- Modify: `scripts/test_runtime_lifecycle.sh`
- Create: `docs/installer-matrix.md`
- Create: `testdata/agent-comparison/windows-paths/mcp.json`
- Create: `testdata/agent-comparison/windows-paths/settings.json`

## Phases

### Phase 1: Lock the Windows and Client Matrix
- [x] Translate the upstream Windows and client reports into a concrete matrix in `docs/gap-analysis.md` that covers path normalization, shell quoting, binary discovery, config locations, and handshake ordering.
- [x] Add fixture config files under `testdata/agent-comparison/windows-paths/` for the shared agent targets and the next client targets the Zig port may claim.
- [x] Record exact temp-home, temp-config, and Windows-path verification commands in `docs/plans/in-progress/windows-installer-and-client-integration-improvements-progress.md`.
- **Status:** complete

### Phase 2: Normalize Installer and Startup Behavior
- [ ] Extend `src/cli.zig`, `src/main.zig`, and `src/discover.zig` so path normalization, binary discovery, project-path validation, and config-file selection behave deterministically across Windows and shared Unix environments.
- [ ] Tighten `src/mcp.zig` and `src/runtime_lifecycle.zig` so handshake ordering, startup notifications, process shutdown, and hook-trigger behavior are explicit and testable rather than inferred from one client’s happy path.
- [ ] Update `scripts/run_cli_parity.sh` and `scripts/test_runtime_lifecycle.sh` so installer and runtime compatibility checks run from fixtures instead of live editor state.
- **Status:** in progress

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, `bash scripts/run_cli_parity.sh`, and `bash scripts/test_runtime_lifecycle.sh` with the new Windows-style fixtures until installer and startup behavior is stable.
- [ ] Update `docs/installer-matrix.md` and `docs/port-comparison.md` only for the agent targets and startup paths that now have explicit evidence.
- [ ] Record remaining unsupported clients, packaging gaps, and trust-related follow-ons in `docs/plans/in-progress/windows-installer-and-client-integration-improvements-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Make client and OS claims only where temp-home fixtures exist | The upstream history shows that live-user environments expose path and config edge cases too late if they are not fixture-tested. |
| Separate installer correctness from broader ecosystem expansion | The port needs a reliable shared core before it grows the supported-client list. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
