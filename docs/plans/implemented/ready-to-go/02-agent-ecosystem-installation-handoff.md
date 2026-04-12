# Handoff: Plan 02 — Agent Ecosystem Installation

**Branch:** create `feat/agent-ecosystem-install` from `main`
**Worktree:** `../worktrees/agent-ecosystem-install`
**Predecessor:** Plan 01 (Packaging) is on `feat/packaging-distribution`, not yet merged to main. Base this work off `main` — there are no source-level dependencies on Plan 01.

## Objective

Expand the Zig installer from its current 2-agent MCP-config-only surface (Codex, Claude Code) to match the C reference's broader agent ecosystem: 10 agent targets, skills installation, hook management, instructions file upsert, and session reminder hooks.

## What already exists in Zig

`src/cli.zig` has:
- `AgentSet` struct with `codex` and `claude` booleans
- `detectAgents()` — checks `~/.codex/` and `~/.claude/` directories
- `installAgentConfigs()` / `uninstallAgentConfigs()` — writes Codex TOML block + Claude JSON MCP entries to 3 paths:
  - `~/.codex/config.toml` (managed block insertion)
  - `~/.claude/.mcp.json` (JSON merge)
  - `~/.claude.json` (legacy JSON merge)
- `InstallReport` with per-agent action tracking (updated/skipped/removed)
- 8 unit tests covering roundtrip, dry-run, detect
- `scripts/run_cli_parity.sh` validates these 2 agents against C reference golden snapshots

## What the C reference does (delta)

### Agent targets (8 missing)

| Agent | Detection | Config format | Instructions file | Hooks |
|-------|-----------|---------------|-------------------|-------|
| Gemini CLI | `~/.gemini/` | `settings.json` (JSON MCP) | `GEMINI.md` | BeforeTool (grep/glob reminder) |
| Zed | Platform-specific app support dir | `settings.json` (nested MCP) | none | none |
| VS Code | Platform-specific User dir | `mcp.json` | none | none |
| OpenCode | PATH lookup (`opencode`) | `opencode.json` | `AGENTS.md` | none |
| Antigravity | `~/.gemini/antigravity/` | `mcp_config.json` | `AGENTS.md` | none |
| KiloCode | `Library/Application Support/Code/...` | `mcp_settings.json` | `codebase-memory-mcp.md` | none |
| Aider | PATH lookup (`aider`) | none (no MCP) | `CONVENTIONS.md` | none |
| OpenClaw | `~/.openclaw/` | `openclaw.json` | none | none |

### Skills installation (missing entirely)

The C reference installs a single consolidated skill file to `~/.claude/skills/codebase-memory/SKILL.md`. Content is embedded in `src/cli/cli.c` as `skill_content[]` (~100 lines of markdown). The installer also removes 4 old monolithic skill files from a prior layout.

Key function: `cbm_install_skills(skills_dir, force, dry_run)` — writes skill content, handles force-overwrite, respects dry-run.

### Hook management (missing entirely)

Two hook types written to `~/.claude/settings.json`:

1. **PreToolUse hook** — reminds the agent to prefer codebase-memory-mcp tools over grep/glob. Written by `cbm_upsert_claude_hooks()`. Matcher: tool-name pattern. Command: shell script at `~/.claude/hooks/cbm-code-discovery-gate`.

2. **Session hooks** — reminds agent on startup/resume/clear/compact to use MCP tools. Written by `cbm_upsert_session_hooks()`. Matchers: `["startup", "resume", "clear", "compact"]`. Command: shell script at `~/.claude/hooks/cbm-session-reminder`.

Both use `upsert_hooks_json()` which merges into the existing hooks array without duplicating.

Gemini gets a similar BeforeTool hook via `cbm_upsert_gemini_hooks()`.

### Instructions file upsert (missing entirely)

`cbm_upsert_instructions(path, content)` — appends/updates a managed section in markdown instruction files (`AGENTS.md`, `GEMINI.md`, `CONVENTIONS.md`). Uses a managed-block pattern (like the Codex TOML block insertion already in Zig) to allow idempotent updates.

Content is in `agent_instructions_content[]` in `cli.c`.

## Implementation approach

### Phase 1: Expand AgentSet and detection

Extend `AgentSet` to include all 10 agents. Implement platform-aware detection for each (home-dir checks, PATH lookups, app-support-dir resolution). Keep the struct flat — each agent is a bool field.

The C reference detection logic is in `cbm_detect_agents()` in `cli.c` around line 2580-2630.

### Phase 2: Skills and hooks infrastructure

Add two new capabilities to `cli.zig`:

1. **`installSkills(skills_dir, force, dry_run)`** — write `SKILL.md` under `skills_dir/codebase-memory/`. Embed skill content as a Zig string literal (port from C's `skill_content[]`). Handle force-overwrite and old-skill cleanup.

2. **`upsertHooks(settings_path, hook_type, matcher, command)`** — generic JSON hook upserter that merges into Claude/Gemini settings without duplicating. Port the managed-block pattern from `upsert_hooks_json()` in C.

3. **`upsertInstructions(path, content)`** — managed-section upsert for markdown files. Similar to the existing Codex TOML managed-block insertion.

### Phase 3: Per-agent install/uninstall

Wire each agent's install flow: detect → write MCP config → write instructions → write skills → write hooks, as applicable per the matrix above. The `installAgentConfigs()` function grows from 2 branches to 10, each calling the appropriate subset.

Update `uninstallAgentConfigs()` correspondingly.

### Phase 4: Hook gate and reminder scripts

The C reference installs two shell scripts:
- `~/.claude/hooks/cbm-code-discovery-gate` (the PreToolUse gate)
- `~/.claude/hooks/cbm-session-reminder` (the session reminder)

These are small shell scripts. Embed them as string literals and write on install.

### Phase 5: Tests and verification

- Extend the existing unit tests to cover new agents
- Add `scripts/test_agent_installation.sh` — temp-HOME harness that runs install/uninstall for all agents and verifies filesystem effects
- Extend `scripts/run_cli_parity.sh` golden snapshots for new agents (coordinate with what the C reference emits)
- Update `docs/port-comparison.md` agent-installation rows

## Key files to read before starting

| File | Why |
|------|-----|
| `src/cli.zig` (full file) | Current Zig install surface — extend this |
| `src/cli/cli.c:2580-2750` in C repo | C reference install orchestration per agent |
| `src/cli/cli.c:396-500` in C repo | Skill content and skill struct |
| `src/cli/cli.c:1139-1200` in C repo | Instructions upsert logic |
| `src/cli/cli.c:1643-1770` in C repo | Hook upsert logic (Claude + Gemini + session) |
| `src/cli/cli.h` in C repo | Agent enum, config structs, hook constants |
| `scripts/run_cli_parity.sh` | Current parity test — extend golden snapshots |

## Gotchas

- **Platform paths:** Zed, VS Code, KiloCode use platform-specific app-support directories (macOS `Library/Application Support/...`, Linux `~/.config/...`, Windows `%APPDATA%`). The C reference has `cbm_agent_config_dir()` with platform switches. Zig's `std.fs` can resolve these but you'll need `@import("builtin").os.tag` branches.
- **PATH detection:** OpenCode and Aider are detected via PATH lookup, not home-dir presence. Use `std.process.getenv("PATH")` and scan.
- **Managed blocks:** The Codex TOML managed-block pattern in `cli.zig` (`# --- cbm managed start ---` / `# --- cbm managed end ---`) is the same pattern needed for markdown instructions upsert. Factor it into a shared helper.
- **JSON hook merge:** The hook upsert must merge into an existing hooks array without duplicating entries. The C reference matches on command path to detect existing entries.
- **Dry-run consistency:** All new write paths must respect the dry-run flag. The existing tests verify this contract.
- **Don't touch packaging:** Plan 01 handles setup scripts and release workflows. This plan is strictly about what `cbm cli install` / `cbm cli uninstall` do post-binary-install.

## Completion criteria

- All 10 agents detected and configured on install
- Skills written to `~/.claude/skills/codebase-memory/SKILL.md`
- Claude hooks (PreToolUse + session) written to `~/.claude/settings.json`
- Gemini hook (BeforeTool) written to Gemini settings
- Instructions files upserted for agents that use them
- Install/uninstall fully reversible (existing test contract)
- Unit tests pass, CLI parity snapshots updated
- `docs/port-comparison.md` agent-installation row updated
- Plan moved to `docs/plans/implemented/ready-to-go/`
