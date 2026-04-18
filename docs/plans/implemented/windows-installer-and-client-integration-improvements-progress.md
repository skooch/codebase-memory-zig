# Windows, Installer, and Client Integration Progress

## Scope

This plan makes the Zig port predictable across Windows-style path roots,
shared Unix config layouts, and MCP client startup behavior.

Current focus:
- explicit config-root selection for runtime cache and client config files
- fixture-backed Windows-style editor and agent config layouts
- temp-home parity checks that do not depend on the host OS layout
- no product-claim expansion beyond the clients and paths we can verify

## Phase 1 Contract

### Current baseline from the implementation

- `src.cli.runtimeCacheDir` currently prefers `CBM_CACHE_DIR`, then falls back
  to `HOME/.cache/codebase-memory-zig` regardless of Windows-style env roots.
- `src.cli.detectAgents` and the Zed, VS Code, and KiloCode install paths are
  currently keyed off the host OS tag, which makes Windows-style layouts hard
  to verify on a non-Windows host.
- `scripts/run_cli_parity.sh` currently exercises the shared Codex and Claude
  temp-home contract, but it does not yet drive fixture-backed Windows path
  layouts.
- `scripts/test_runtime_lifecycle.sh` already covers the completed runtime
  lifecycle baseline and should remain green while this plan adjusts client
  startup behavior.

### Matrix to lock

- runtime cache root
  - `CBM_CACHE_DIR`
  - Windows `LOCALAPPDATA`
  - Unix `XDG_CACHE_HOME`
  - `HOME` fallback
- roaming config root
  - Windows `APPDATA`
  - Unix `XDG_CONFIG_HOME`
  - macOS `~/Library/Application Support`
- client config file selection
  - Codex CLI
  - Claude Code
  - Zed
  - VS Code
  - KiloCode
- startup and runtime checks
  - `initialize`
  - one-shot update notice
  - graceful EOF and SIGTERM shutdown

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_cli_parity.sh --zig-only
bash scripts/test_runtime_lifecycle.sh
```

### First implementation slice

- factor client and runtime path selection behind an explicit config-platform
  helper instead of relying only on the host OS tag
- add Windows-style fixture files under `testdata/agent-comparison/windows-paths/`
- keep the first verification slice focused on path resolution and temp-home
  determinism before touching handshake ordering

## Phase 2 Checkpoint: Config-Platform Path Substrate

Implementation on 2026-04-18:

- `src/cli.zig`
  - added explicit config-platform selection with `CBM_CONFIG_PLATFORM`
  - taught `runtimeCacheDir` to resolve Windows `LOCALAPPDATA` and Unix
    `XDG_CACHE_HOME` roots through the shared helper substrate
  - moved Zed, VS Code, and KiloCode path selection behind shared helpers so
    detection and install/uninstall flows no longer depend only on the host OS
    tag
  - added focused unit coverage for Windows-style runtime cache and client
    config paths
- `testdata/agent-comparison/windows-paths/`
  - added Windows-style VS Code and Zed fixture configs to anchor later parity
    and installer-matrix checks

Verification for this slice:

```sh
zig build test
bash scripts/run_cli_parity.sh --zig-only
bash scripts/test_runtime_lifecycle.sh
```

Results:

- `zig build test` passed
- `bash scripts/run_cli_parity.sh --zig-only` passed with `18` shared checks
  matching the golden snapshot
- `bash scripts/test_runtime_lifecycle.sh` passed:
  - clean EOF shutdown
  - SIGTERM shutdown
  - one-shot startup update notice

## Phase 2 Checkpoint: Fixture-Backed Windows CLI Lane

Second implementation slice on 2026-04-18:

- `scripts/run_cli_parity.sh`
  - added a Windows-layout fixture lane for `--zig-only` and `--update-golden`
  - seeds VS Code and Zed config files from
    `testdata/agent-comparison/windows-paths/`
  - runs `install --force` and `config set auto_index true` under
    `CBM_CONFIG_PLATFORM=windows` with explicit `APPDATA` and `LOCALAPPDATA`
  - snapshots a separate `windows_contract` alongside the existing
    shared-agent contract
- `testdata/interop/golden/cli-parity.json`
  - now records the Windows-layout expectations:
    - runtime config under `LOCALAPPDATA`
    - VS Code, Zed, and KiloCode config writes under `APPDATA`

Verification for this slice:

```sh
bash scripts/run_cli_parity.sh --update-golden
bash scripts/run_cli_parity.sh --zig-only
```

Results:

- refreshed the golden snapshot with the new `windows_contract`
- `bash scripts/run_cli_parity.sh --zig-only` passed with `23` total checks
  matching the golden snapshot

## Phase 2 Checkpoint: Silent Startup Notifications

Third implementation slice on 2026-04-18:

- `src/mcp.zig`
  - now ignores JSON-RPC notifications with no `id` instead of trying to
    dispatch them like normal requests
  - adds focused regression coverage for silent notifications and for the
    `notifications/initialized` path not stealing the one-shot update notice
- `scripts/test_runtime_lifecycle.sh`
  - now drives `initialize`, `notifications/initialized`, and `tools/list`
  - verifies that the notification produces no response and that the first real
    tool response still receives the startup update notice

Verification for this slice:

```sh
zig build
zig build test
bash scripts/run_cli_parity.sh
bash scripts/run_cli_parity.sh --zig-only
bash scripts/test_runtime_lifecycle.sh
```

Results:

- `zig build` passed
- `zig build test` passed
- `bash scripts/run_cli_parity.sh` passed with no Zig/C shared-contract
  mismatches
- `bash scripts/run_cli_parity.sh --zig-only` passed with `23` total checks
  matching the golden snapshot
- `bash scripts/test_runtime_lifecycle.sh` passed:
  - clean EOF shutdown
  - SIGTERM shutdown
  - one-shot startup update notice
  - silent `notifications/initialized`

## Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, `bash scripts/run_cli_parity.sh`, and
  `bash scripts/test_runtime_lifecycle.sh` with the new Windows-style fixtures
  until installer and startup behavior is stable.
- [x] Update `docs/installer-matrix.md` and `docs/port-comparison.md` only for
  the agent targets and startup paths that now have explicit evidence.
- [x] Record remaining unsupported clients, packaging gaps, and trust-related
  follow-ons in this progress file.
- **Status:** complete

## Phase 3 Completion Pass

Final plan verification on 2026-04-18:

```sh
zig build
zig build test
bash scripts/run_cli_parity.sh
bash scripts/run_cli_parity.sh --zig-only
bash scripts/test_runtime_lifecycle.sh
```

Results:

- `zig build` passed
- `zig build test` passed
- `bash scripts/run_cli_parity.sh` passed
- `bash scripts/run_cli_parity.sh --zig-only` passed
- `bash scripts/test_runtime_lifecycle.sh` passed

Remaining intentional gaps:

- shipped support scope remains Codex CLI plus Claude Code even though the repo
  now has fixture-backed Windows-layout config-writer evidence for VS Code,
  Zed, and KiloCode
- packaging trust, signing, archive behavior, and setup-script parity remain
  separate follow-on work rather than something this plan claims to finish
