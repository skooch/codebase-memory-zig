# Installer And Client Matrix

Refresh date: 2026-04-19

This matrix records only the installer and startup paths that have explicit
fixture or harness evidence in this repo. It is not a wish list.

## Verified Roots

| Surface | Verified roots | Evidence |
|--------|----------------|----------|
| Runtime config cache | `CBM_CACHE_DIR`, Windows `LOCALAPPDATA`, Unix `XDG_CACHE_HOME`, `HOME` fallback | `src/cli.zig` unit tests plus `bash scripts/run_cli_parity.sh --zig-only` |
| Roaming client config roots | Windows `APPDATA`, Unix `XDG_CONFIG_HOME`, macOS `~/Library/Application Support` | `src/cli.zig` unit tests |
| Broader temp-home agent paths | `~/.codex/config.toml`, `~/.claude/.mcp.json`, `~/.claude.json`, `~/.gemini/settings.json`, `~/.gemini/antigravity/mcp_config.json`, `~/.config/opencode/opencode.json`, `~/.openclaw/openclaw.json`, `~/Library/Application Support/Zed/settings.json`, `~/Library/Application Support/Code/User/mcp.json`, `~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` | `bash scripts/run_cli_parity.sh --zig-only` |
| Broader temp-home extras | `~/.claude/hooks/*`, `~/.claude/skills/codebase-memory/SKILL.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/antigravity/AGENTS.md`, `~/CONVENTIONS.md`, `~/.kilocode/rules/codebase-memory-mcp.md` | `bash scripts/run_cli_parity.sh --zig-only` |
| Windows-layout editor fixtures | `APPDATA/Code/User/mcp.json`, `APPDATA/Zed/settings.json`, `APPDATA/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` | `bash scripts/run_cli_parity.sh --zig-only` |

## Verified Installer Matrix

| Client | Config path shape | Verified side effects | Evidence |
|--------|-------------------|--------|----------|
| Codex CLI | `~/.codex/config.toml` | MCP config, managed `AGENTS.md`, uninstall cleanup while preserving user blocks | `bash scripts/run_cli_parity.sh`, `--zig-only` |
| Claude Code | `~/.claude/.mcp.json` and `~/.claude.json` | Dual MCP config, hook JSON, gate script, reminder script, consolidated skill package, uninstall cleanup while preserving user keys | `bash scripts/run_cli_parity.sh`, `--zig-only` |
| Gemini | `~/.gemini/settings.json` | MCP config, `BeforeTool` hook, `GEMINI.md`, uninstall cleanup while preserving user keys | `bash scripts/run_cli_parity.sh --zig-only` |
| Zed | `~/Library/Application Support/Zed/settings.json` and Windows `APPDATA/Zed/settings.json` | MCP config writer and remover | `bash scripts/run_cli_parity.sh --zig-only` |
| OpenCode | `~/.config/opencode/opencode.json` | MCP config, `AGENTS.md`, uninstall cleanup | `bash scripts/run_cli_parity.sh --zig-only` |
| Antigravity | `~/.gemini/antigravity/mcp_config.json` | MCP config, `AGENTS.md`, uninstall cleanup | `bash scripts/run_cli_parity.sh --zig-only` |
| Aider | `~/CONVENTIONS.md` | Instruction file install/remove through PATH-based detection | `bash scripts/run_cli_parity.sh --zig-only` |
| KiloCode | `~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` and Windows `APPDATA/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json` | MCP config, rules file, uninstall cleanup | `bash scripts/run_cli_parity.sh --zig-only` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json` and Windows `APPDATA/Code/User/mcp.json` | MCP config writer and remover | `bash scripts/run_cli_parity.sh --zig-only` |
| OpenClaw | `~/.openclaw/openclaw.json` | MCP config writer and remover | `bash scripts/run_cli_parity.sh --zig-only` |

## Verified Command Behavior

| Behavior | Status | Evidence |
|---------|--------|----------|
| Detected-scope `install` reports the broader 10-agent matrix | Verified | `bash scripts/run_cli_parity.sh --zig-only` |
| Detected-scope `update --dry-run` succeeds for the broader 10-agent matrix | Verified | `bash scripts/run_cli_parity.sh --zig-only` |
| Detected-scope `uninstall` removes the broader 10-agent matrix while preserving seeded user config | Verified | `bash scripts/run_cli_parity.sh --zig-only` |
| Shared Codex/Claude install/update/uninstall behavior still matches the original C binary | Verified | `bash scripts/run_cli_parity.sh` |

## Verified Startup Behavior

| Behavior | Status | Evidence |
|---------|--------|----------|
| `initialize` response | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| One-shot startup update notice | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| `notifications/initialized` produces no response | Verified | `bash scripts/test_runtime_lifecycle.sh` and `src/mcp.zig` tests |
| EOF shutdown | Verified | `bash scripts/test_runtime_lifecycle.sh` |
| SIGTERM shutdown | Verified | `bash scripts/test_runtime_lifecycle.sh` |

## Explicitly Not Claimed Yet

- Binary self-replacement parity with the original `update` flow
- The original multi-skill Claude layout; Zig currently ships one consolidated
  `codebase-memory` skill package instead
- Windows-native process execution, archive, or shell behavior outside the
  fixture-backed path and config-root contract
- Packaging trust, release signing, or setup-script parity
