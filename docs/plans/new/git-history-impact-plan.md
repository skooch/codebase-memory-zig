# Plan: Git History Impact Parity

## Goal
Add git-history-derived graph facts so the Zig port can model `FILE_CHANGES_WITH` and the broader history-coupled impact analysis the original exposes.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/git-history-impact-plan.md`
- Create: `docs/plans/new/git-history-impact-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/git_history.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/store_test.zig`
- Modify: `src/mcp.zig`
- Create: `testdata/git-history/repo-seed.sh`

## Phases

### Phase 1: Lock the History Contract
- [ ] Re-read the original git-history pass and capture the overlapping commit-window, co-change, and persistence rules in `docs/gap-analysis.md`.
- [ ] Add `testdata/git-history/repo-seed.sh` to create a deterministic local git repo for history-backed verification.
- [ ] Record the exact verification commands for history ingestion and co-change queries in `docs/plans/new/git-history-impact-progress.md`.
- **Status:** pending

### Phase 2: Implement History-Derived Graph Facts
- [ ] Add `src/git_history.zig` to mine commit history and emit `FILE_CHANGES_WITH` relationships without entangling the core extractor passes.
- [ ] Extend `src/pipeline.zig`, `src/store.zig`, `src/store_test.zig`, and `src/mcp.zig` so co-change data is stored, queryable, and available to impact-analysis features.
- [ ] Add regression coverage for commit-window parsing, co-change scoring, and duplicate-edge handling.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and the seeded git-history fixture until `FILE_CHANGES_WITH` queries match the supported contract.
- [ ] Update `docs/port-comparison.md` so the git-history and `FILE_CHANGES_WITH` rows move out of `Deferred` only after the local seeded repo proves them.
- [ ] Record any remaining intentionally skipped history dimensions in `docs/plans/new/git-history-impact-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Use a seeded local repo fixture | History-derived features need deterministic commit graphs, and a generated local repo is easier to keep reproducible than a shared long-lived fixture checkout. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
