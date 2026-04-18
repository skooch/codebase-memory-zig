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

## Phase 2 Checkpoint: Broader Installer Matrix Harness

Implementation slice on 2026-04-19:

- `src/main.zig`
  - now prints the broader detected-agent matrix in install/update/uninstall
    output instead of only Codex CLI and Claude Code
  - no longer treats detected-scope installs or updates as failures just
    because only non-shipped targets were found
- `src/cli.zig`
  - now exposes scope-aware detected-agent helpers so the CLI success path is
    driven by the real target matrix instead of a hard-coded shared pair
- `scripts/run_cli_parity.sh`
  - now seeds `testdata/cli-agent-fixtures/`
  - now proves broader detected-scope install, update, and uninstall behavior
    for:
    - Codex CLI
    - Claude Code
    - Gemini
    - Zed
    - OpenCode
    - Antigravity
    - Aider
    - KiloCode
    - VS Code
    - OpenClaw
  - now verifies broader auxiliary side effects:
    - Claude hooks
    - Claude reminder script
    - Claude consolidated skill package
    - Codex instructions
    - Gemini hooks and instructions
    - OpenCode instructions
    - Antigravity instructions
    - Aider instructions
    - KiloCode rules
- `testdata/cli-agent-fixtures/`
  - now holds the pre-existing user-config seeds that the temp-home harness
    must preserve across install and uninstall

Verification for this slice:

```sh
zig build
zig build test
bash scripts/run_cli_parity.sh --update-golden
bash scripts/run_cli_parity.sh --zig-only
bash scripts/run_cli_parity.sh
```

Results:

- `zig build` passed
- `zig build test` passed
- `bash scripts/run_cli_parity.sh --update-golden` refreshed the installer
  matrix golden snapshot with the new broader contract
- `bash scripts/run_cli_parity.sh --zig-only` passed with `98` matching checks
- `bash scripts/run_cli_parity.sh` passed with zero shared Zig/C mismatches on
  the overlapping Codex/Claude contract

## Phase 3 Checkpoint: Docs Reclassification And Residual Delta

Completion pass on 2026-04-19:

- `docs/installer-matrix.md`
  - now lists the verified broader 10-agent detected-scope matrix and the
    verified auxiliary-file roots
- `docs/port-comparison.md`
  - now reflects that the broader detected-scope installer matrix is real and
    verified, while still keeping productization overall below full parity
    because binary self-replacement and the original multi-skill Claude layout
    are still different
- `docs/gap-analysis.md`
  - now records the implemented installer-ecosystem slice and narrows the
    remaining productization backlog to:
    - binary self-replacement parity
    - any future side effects beyond the already-verified ten-agent matrix

Residual delta after completion:

- the shipped default scope remains intentionally `shipped`
- binary self-replacement remains deferred in the Zig `update` flow
- Claude skills are intentionally packaged as one consolidated
  `codebase-memory` skill instead of the original multi-skill layout
