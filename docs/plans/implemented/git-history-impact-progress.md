# Git History Impact Progress

## Status
Complete. Git-history coupling is implemented through `src/git_history.zig` and
covered by `src/git_history_test.zig`.

## Implemented Scope
- Mines bounded `git log` output through a subprocess rather than libgit2.
- Filters generated, vendor, lock, binary, and cache paths before scoring.
- Computes file-pair co-change counts and coupling scores.
- Emits `FILE_CHANGES_WITH` edges with `co_changes` and `coupling_score`
  properties for matching file nodes.
- Runs from the pipeline as a non-fatal enrichment pass.

## Verification
- `zig build`
- `zig build test`
- Direct coverage in `src/git_history_test.zig`:
  - trackable-file filtering
  - coupling computation
  - empty history handling
  - graph-buffer edge creation
  - duplicate-edge handling
  - missing-file skip behavior

## Deferred
- No libgit2 dependency.
- No unbounded full-history mining.
- No graph claim beyond `FILE_CHANGES_WITH` until route/config graph-model
  parity work adds additional verified facts.
