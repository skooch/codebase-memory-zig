# Installer And Client Matrix

Refresh date: 2026-04-18

This matrix records only the installer and startup paths that have explicit
fixture or harness evidence in this repo. It is not a wish list.

## Verified Roots

| Surface | Verified roots | Evidence |
|--------|----------------|----------|
| Runtime config cache | `CBM_CACHE_DIR`, Windows `LOCALAPPDATA`, Unix `XDG_CACHE_HOME`, `HOME` fallback | `src/cli.zig` unit tests plus `bash scripts/run_cli_parity.sh --zig-only` |
| Roaming client config roots | Windows `APPDATA`, Unix `XDG_CONFIG_HOME`, macOS `~/Library/Application Support` | `src/cli.zig` unit tests |
| Shared temp-home agent paths | `~/.codex/config.toml`, `~/.claude/.mcp.json`, `~/.claude.json` | `bash scripts/run_cli_parity.sh` and `--zig-only` |
| Windows-layout editor fixtures | `APPDATA/Code/User/mcp.json`, `APPDATA/Zed/settings.json`, `APPDATA/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` | `bash scripts/run_cli_parity.sh --zig-only` |

## Verified Client Paths

| Client | Config path shape | Status | Evidence |
|--------|-------------------|--------|----------|
| Codex CLI | `~/.codex/config.toml` | Verified | Shared CLI parity harness |
| Claude Code | `~/.claude/.mcp.json` and `~/.claude.json` | Verified | Shared CLI parity harness |
| VS Code | `APPDATA/Code/User/mcp.json` on Windows-style fixtures | Verified for config writer | Windows fixture lane in `run_cli_parity.sh --zig-only` |
| Zed | `APPDATA/Zed/settings.json` on Windows-style fixtures | Verified for config writer | Windows fixture lane in `run_cli_parity.sh --zig-only` |
| KiloCode | `APPDATA/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` on Windows-style fixtures | Verified for config writer | Windows fixture lane in `run_cli_parity.sh --zig-only` |

## Verified Startup Behavior

| Behavior | Status | Evidence |
|---------|--------|----------|
| `initialize` response | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| One-shot startup update notice | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| `notifications/initialized` produces no response | Verified | `bash scripts/test_runtime_lifecycle.sh` and `src/mcp.zig` tests |
| EOF shutdown | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| SIGTERM shutdown | Verified | `bash scripts/test_runtime_lifecycle.sh` |

## Explicitly Not Claimed Yet

- Broad agent auto-detection parity beyond the current shipped Codex CLI and
  Claude Code scope
- Windows-native process execution, archive, or shell behavior outside the
  fixture-backed path and config-root contract
- Packaging trust, release signing, or setup-script parity
