# Progress: Detect Changes Since Parity

## 2026-04-21

- Started the `detect_changes.since` slice in
  `docs/plans/implemented/18-detect-changes-since-parity-plan.md`.
- Confirmed the current Zig path uses `base_branch` only:
  - `src/mcp.zig` exposes `project`, `base_branch`, `scope`, and `depth`
  - `src/query_router.zig` diffs `base_branch...HEAD` plus the dirty worktree
- Confirmed the released upstream `v0.6.0` `tools/list` schema advertises a
  `since` field for `detect_changes`, described as:
  - `Git ref or date to compare from (e.g. HEAD~5, v0.5.0, 2026-01-01)`
- Confirmed the released upstream C implementation still does not consume that
  `since` field in `handle_detect_changes()`, so this slice is a Zig-side
  contract-completion step against the released surface rather than a local
  full-compare step against the stale C checkout.
- Implemented the Zig-side selector path:
  - `src/mcp.zig` now advertises `since` in `tools/list`, parses it in
    `detect_changes`, and returns `Invalid since selector` on bad input.
  - `src/query_router.zig` now resolves `since` before diffing, with
    commit-ish refs handled through `git rev-parse` and date selectors gated to
    strict ISO `YYYY-MM-DD` values before calling `git rev-list`.
- Added direct unit coverage for:
  - the `tools/list` `since` schema
  - commit-ish `since` resolution via `HEAD~1`
  - ISO-date `since` resolution via `2026-04-19`
  - invalid-selector rejection
- The first verification attempt failed because the linked worktree was missing
  vendored tree-sitter headers; `bash scripts/bootstrap_worktree.sh
  /Users/skooch/projects/codebase-memory-zig` repaired the worktree inputs.
- Final verification for this slice:
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`39/39`)
