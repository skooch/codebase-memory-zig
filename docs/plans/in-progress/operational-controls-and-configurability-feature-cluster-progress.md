# Operational Controls and Configurability Progress

## Scope

This plan makes the Zig port's operational knobs explicit and testable instead
of leaving them split across runtime env vars, config keys, and installer-side
defaults.

Current focus:
- cache-root, config-root, and install-scope controls
- startup and watcher trigger behavior
- runtime lifecycle and update-check switches
- CLI progress and other operator-facing ergonomics
- fixture-backed verification that avoids touching a real home directory

## Phase 1 Contract

### Current baseline from the implementation

- `src/cli.zig` already exposes a small persisted config surface:
  - `auto_index`
  - `auto_index_limit`
  - `download_url`
- `src/cli.zig` already honors several env-driven path controls:
  - `CBM_CONFIG_PLATFORM`
  - `CBM_CACHE_DIR`
  - `LOCALAPPDATA`
  - `APPDATA`
  - `XDG_CACHE_HOME`
  - `XDG_CONFIG_HOME`
- `src/main.zig` already exposes some runtime-only env switches:
  - `CBM_AUTO_INDEX`
  - `CBM_AUTO_INDEX_LIMIT`
  - `CBM_IDLE_STORE_TIMEOUT_MS`
  - `--progress` for `cbm cli`
- `src/runtime_lifecycle.zig` already exposes update-check controls:
  - `CBM_UPDATE_CHECK_DISABLE`
  - `CBM_UPDATE_CHECK_LATEST`
  - `CBM_UPDATE_CHECK_CURRENT`
  - `CBM_UPDATE_CHECK_URL`
- install/update flows currently expose action flags rather than a richer
  install-scope matrix:
  - `-y` / `--yes`
  - `-n` / `--no`
  - `--dry-run`
  - `--force`

### Control buckets to lock

- installer scope and config portability
  - supported-agent selection remains implicit today
  - path portability exists, but scope selection is still narrow
- cache and config location
  - runtime DB/config path roots
  - per-platform roaming config roots
- runtime trigger behavior
  - startup auto-index
  - auto-index file-count cap
  - idle runtime-store eviction
  - update-check behavior
- operator-facing runtime output
  - `cli --progress`
  - explicit config inspection via `cbm config`
- currently absent or still-deferred operational surfaces
  - host bind/listen control for non-stdio serving
  - explicit hook policy controls beyond the current installer baseline
  - custom extension mapping and other broader user-config surfaces

### Fixture area for this plan

- `testdata/interop/configuration/env-overrides/`
  - documents the temp-home and env-override lanes this plan will turn into
    repeatable checks before changing product claims

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_cli_parity.sh --zig-only
```

### First implementation slice

- move the plan into `in-progress` and lock the actual control-surface matrix
  in docs before changing code
- add the configuration fixture area so later env/config verification does not
  depend on a developer home directory
- keep host-binding and broader hook claims explicitly marked as absent until
  the code exposes a real control surface for them

## Phase 1 Checkpoint: Control-Surface Inventory

Plan-start pass on 2026-04-19:

- verified the current operational knobs by local inspection after
  `codebase-memory-mcp` failed with `Transport closed`
- confirmed the starting config/runtime surface is real but fragmented rather
  than broad:
  - persisted config keys live in `src/cli.zig`
  - startup/index/runtime env overrides live in `src/main.zig`
  - update-check overrides live in `src/runtime_lifecycle.zig`
- confirmed this plan should treat host binding and broader installer-scope
  controls as currently missing, not as hidden features waiting to be
  documented

Verification for this slice:

```sh
git status --short --branch
```

Results:

- worktree confirmed at `/Users/skooch/projects/worktrees/operational-controls`
  on `codex/operational-controls`
- plan state corrected from `new/` to `in-progress/` for this worktree
