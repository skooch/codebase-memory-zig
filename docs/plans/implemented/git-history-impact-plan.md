# Plan: Git History Impact Parity

## Goal
Add git-history-derived graph facts so the Zig port can model `FILE_CHANGES_WITH` and the broader history-coupled impact analysis the original exposes.

## Current Phase
All phases complete

## File Map
- Modify: `docs/plans/implemented/git-history-impact-plan.md`
- Create: `docs/plans/implemented/git-history-impact-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/git_history.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/store_test.zig`
- Modify: `src/mcp.zig`
- Create: `src/git_history_test.zig`

## Phases

### Phase 1: Lock the History Contract
- [x] Re-read the original git-history pass and capture the overlapping commit-window, co-change, and persistence rules in `docs/gap-analysis.md`.
- [x] Add deterministic unit and graph-buffer tests in `src/git_history_test.zig` for parsing, scoring, duplicate handling, and `FILE_CHANGES_WITH` persistence.
- [x] Record the exact verification commands for history ingestion and co-change queries in `docs/plans/implemented/git-history-impact-progress.md`.
- **Status:** complete

### Phase 2: Implement History-Derived Graph Facts
- [x] Add `src/git_history.zig` to mine commit history and emit `FILE_CHANGES_WITH` relationships without entangling the core extractor passes.
- [x] Extend `src/pipeline.zig`, `src/store.zig`, `src/store_test.zig`, and `src/mcp.zig` so co-change data is stored, queryable, and available to impact-analysis features.
- [x] Add regression coverage for commit-window parsing, co-change scoring, and duplicate-edge handling.
- **Status:** complete

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and the git-history regression tests until `FILE_CHANGES_WITH` queries match the supported contract.
- [x] Update `docs/port-comparison.md` so the git-history and `FILE_CHANGES_WITH` rows move out of `Deferred` only after the local seeded repo proves them.
- [x] Record any remaining intentionally skipped history dimensions in `docs/plans/implemented/git-history-impact-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep verification deterministic | History-derived features need deterministic commit graphs, so regression coverage uses parsed sample commits and graph-buffer assertions instead of a live external repository. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
