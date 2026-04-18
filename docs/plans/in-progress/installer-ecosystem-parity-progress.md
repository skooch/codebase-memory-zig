# Installer Ecosystem Parity Progress

## Scope

This plan closes the gap between the Zig port's currently shipped two-agent
installer claim and the broader ten-agent installer surface that already exists
in code but is under-verified and under-documented.

Current focus:
- lock the original installer matrix and the Zig branch's real current surface
- prove broader agent install, uninstall, hooks, instructions, and reminder
  side effects in temp-home fixtures
- make CLI install output reflect the broader detected-agent matrix
- reclassify productization docs only where fixture-backed evidence exists

## Phase 1 Contract

### Current baseline from the implementation

- `src/cli.zig` already detects and manages a broader installer matrix:
  - `Codex CLI`
  - `Claude Code`
  - `Gemini`
  - `Zed`
  - `OpenCode`
  - `Antigravity`
  - `Aider`
  - `KiloCode`
  - `VS Code`
  - `OpenClaw`
- extras already exist in the Zig implementation:
  - Claude skills
  - Claude hooks, including the session reminder script
  - Codex instructions
  - Gemini instructions and hooks
  - OpenCode instructions
  - Antigravity instructions
  - Aider instructions
  - KiloCode rules/instructions
- the main missing proof surface is not raw support but evidence:
  - `scripts/run_cli_parity.sh` only locks the shared Codex/Claude overlap,
    operational controls, and a Windows config-writer lane
  - `printInstallReport` in `src/main.zig` only reports the shared shipped pair
    even when a detected-scope install manages more targets

### Original installer matrix to lock

- `Claude Code`
  - nested and legacy MCP config entries
  - hooks
  - reminder script
  - skills
- `Codex CLI`
  - MCP config
  - `AGENTS.md`
- `Gemini`
  - MCP config
  - hooks
  - `GEMINI.md`
- `Zed`
  - MCP config
- `OpenCode`
  - MCP config
  - `AGENTS.md`
- `Antigravity`
  - MCP config
  - `AGENTS.md`
- `Aider`
  - `CONVENTIONS.md`
- `KiloCode`
  - MCP config
  - rules file
- `VS Code`
  - MCP config
- `OpenClaw`
  - MCP config

### Fixture area for this plan

- `testdata/cli-agent-fixtures/`
  - seed files for pre-existing user config that the temp-home harness must
    preserve while managed MCP blocks are inserted and later removed

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_cli_parity.sh --update-golden
bash scripts/run_cli_parity.sh --zig-only
bash scripts/run_cli_parity.sh
```

## Phase 1 Checkpoint: Matrix Reset

Plan-start pass on 2026-04-19:

- re-read the original installer smoke tests and current Zig installer code
- confirmed the branch already implements the broader ten-agent target matrix
  and most auxiliary side effects
- identified the real remaining gap as proof and reporting rather than a blank
  installer implementation:
  - broader temp-home verification is missing
  - CLI install/update/uninstall output does not enumerate the broader detected
    targets
- confirmed this plan should keep any remaining delta focused on:
  - consolidated Zig Claude skill packaging versus the original multi-skill
    layout
  - intentionally narrower shipped scope defaults
  - any auxiliary effects the new harness proves are still missing

Verification for this slice:

```sh
git status --short --branch
```

Results:

- worktree confirmed at
  `/Users/skooch/projects/worktrees/installer-ecosystem-parity`
  on `codex/installer-ecosystem-parity`
- plan state corrected from `new/` to `in-progress` before implementation
