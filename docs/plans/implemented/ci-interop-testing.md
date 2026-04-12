# A15: CI Interop Testing

**Origin:** Architecture review issue A15 (2026-04-12)
**Status:** New
**Size:** L
**Blocked by:** Access to the C reference binary in CI

## Problem

The interop parity harness (`scripts/run_interop_alignment.sh`) compares Zig MCP output against the C reference implementation (`../codebase-memory-mcp/build/c/codebase-memory-mcp`). It runs locally but is not gated in CI, so regressions in Zig/C parity go undetected until manual runs.

A second script (`scripts/run_cli_parity.sh`) compares CLI install/uninstall/update behavior between implementations and has the same gap.

## What Already Exists

### Test fixtures
- `testdata/interop/manifest.json` — declares fixtures, tool assertions, expected results
- `testdata/interop/` — 10+ fixture directories (python-basic, javascript-basic, rust-parity, adr-parity, scip, test-tagging, etc.)

### Harness scripts
- `scripts/run_interop_alignment.sh` — full MCP protocol comparison harness
  - Spins up both binaries as MCP stdio servers
  - Sends identical JSON-RPC sequences (initialize, tools/list, index_repository, search_graph, query_graph, trace_call_path, etc.)
  - Canonicalizes outputs for comparison (normalizes paths, sorts, strips impl-specific fields)
  - Writes JSON + markdown reports to `.interop_reports/`
  - Env vars: `CODEBASE_MEMORY_C_BIN`, `CODEBASE_MEMORY_ZIG_BIN`
- `scripts/run_cli_parity.sh` — CLI install/uninstall contract comparison
  - Env vars: `CODEBASE_MEMORY_C_BIN`, `CODEBASE_MEMORY_ZIG_BIN`

### Key implementation details
- Both scripts are Python 3.9-compatible (inline heredoc Python, no type union syntax)
- C binary path resolution: tries `../codebase-memory-mcp/build/c/codebase-memory-mcp`, falls back to `../../codebase-memory-mcp/build/c/codebase-memory-mcp` (for worktrees)
- Zig binary: built via `zig build` into `zig-out/bin/cbm`, or via `$CODEBASE_MEMORY_ZIG_BIN`
- C binary project names use path-based naming (`normalize_project_name_for_c`), Zig uses basename
- `trace_call_path` has an extra qualified_name resolution step for Zig (C uses `function_name` directly)

### CI workflow
- `.github/workflows/ci.yml` — runs format check, build, test, zlint
- No interop step today

## Approach Options

### Option A: Build C binary in CI from source
Add a CI job that:
1. Clones `codebase-memory-mcp` repo
2. Builds the C binary (requires CMake + yyjson + Mongoose + SQLite deps)
3. Runs `scripts/run_interop_alignment.sh` with both binaries
4. Uploads report as artifact

**Pros:** Full parity coverage, catches regressions in both directions.
**Cons:** CI time (~5 min for C build), dependency on external repo staying buildable, CMake + C deps on Ubuntu runner.

### Option B: Pre-built C binary as release artifact
- Publish C binary as a GitHub release artifact from the C repo
- Download it in CI via `gh release download` or curl

**Pros:** Fast CI, no C build deps.
**Cons:** Requires C repo release discipline, binary may drift from C repo HEAD.

### Option C: Zig-only mode with golden snapshots
- Run interop harness with Zig only (skip C comparison)
- Compare Zig output against checked-in golden JSON snapshots
- Periodically update snapshots from full C comparison runs

**Pros:** No C dependency in CI, still catches Zig regressions.
**Cons:** Doesn't catch C drift, snapshot maintenance.

## Recommended: Option A for nightly, Option C for PR checks

- **PR checks:** Run `run_interop_alignment.sh` in Zig-only mode against golden snapshots. Fast, no external deps.
- **Nightly/weekly:** Build C from source, run full comparison, update golden snapshots if both pass.

## Implementation Checklist

1. **Add Zig-only snapshot mode to interop harness**
   - New flag: `--zig-only` or `--snapshot-mode`
   - When set, skip C binary, compare Zig output against `testdata/interop/golden/*.json`
   - Exit non-zero on mismatch
   - Size: M

2. **Generate initial golden snapshots**
   - Run full harness locally, capture Zig canonical outputs
   - Check in under `testdata/interop/golden/`
   - Size: S

3. **Add CI job for PR checks**
   - New job in `.github/workflows/ci.yml` after `Run tests`
   - Runs `scripts/run_interop_alignment.sh --zig-only`
   - Size: S

4. **Add nightly CI workflow for full comparison**
   - New `.github/workflows/interop-nightly.yml`
   - Scheduled cron, clones + builds C repo
   - Runs full comparison, uploads report artifact
   - Opens issue on new mismatches (optional)
   - Size: M

5. **Add CLI parity to CI**
   - Same split: snapshot mode for PR, full comparison for nightly
   - Size: S

## Files to touch
- `scripts/run_interop_alignment.sh` — add `--zig-only` / `--snapshot` flag
- `scripts/run_cli_parity.sh` — add `--zig-only` flag
- `testdata/interop/golden/` — new directory for golden snapshots
- `.github/workflows/ci.yml` — add interop check step
- `.github/workflows/interop-nightly.yml` — new nightly workflow

## Risks
- C repo build may break independently (mitigated by nightly-only full comparison)
- Golden snapshots need updating when Zig behavior intentionally changes
- Python 3.9 constraint on inline heredoc (no `X | Y` type syntax — already documented in CLAUDE.md)
