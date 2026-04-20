# Plan: Detect Changes Since Parity

## Goal
Close the latest-upstream `detect_changes.since` gap by implementing the
advertised baseline selector in the Zig MCP surface with direct verification.

## Current Phase
Completed

## File Map
- Modify: `src/query_router.zig`
- Modify: `src/mcp.zig`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`
- Modify: `docs/plans/new/README.md`
- Create: `docs/plans/implemented/18-detect-changes-since-parity-progress.md`

## Phases

### Phase 1: Lock the `since` contract
- [x] Re-read the released upstream `v0.6.0` `detect_changes` schema and
      implementation to distinguish the advertised `since` surface from the
      older local C behavior.
- [x] Decide how Zig should resolve `since` values across commit-ish refs and
      date strings, and how that interacts with `base_branch`.
- **Status:** completed

### Phase 2: Implement the selector
- [x] Add `since` to the Zig `detect_changes` MCP schema and request parsing.
- [x] Teach the query layer to resolve `since` to a concrete git baseline and
      diff against that baseline plus the dirty worktree.
- [x] Return a clear invalid-argument error when `since` cannot be resolved.
- **Status:** completed

### Phase 3: Verify and reclassify
- [x] Add focused unit coverage for commit-ish `since`, date-style `since`, the
      `tools/list` schema, and invalid-selector behavior.
- [x] Update the parity docs so `detect_changes` no longer overstates the
      remaining latest-upstream gap after `since` lands.
- [x] Move this plan to `implemented` only after the verification stack is
      green.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat `since` as a Zig-side contract closure even though the local C reference does not implement it | The latest released upstream schema advertises `since`, so the port-state docs should be driven by the released contract, not only the stale local checkout. |
| Keep the change scoped to `detect_changes` | This closes a real latest-upstream tool-contract gap without dragging in the larger `moderate` or semantic-search work. |
| Accept strict ISO calendar dates on the date path | Git's loose natural-language date parsing will happily reinterpret garbage strings, so Zig must validate the date shape itself if it wants a trustworthy invalid-selector error. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Verification failed on missing `vendored/tree_sitter/tree_sitter/parser.h` in the worktree | Re-ran `zig build` and `zig build test` after the first failure | Repaired the worktree vendored inputs with `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig` before rerunning the verification stack. |
