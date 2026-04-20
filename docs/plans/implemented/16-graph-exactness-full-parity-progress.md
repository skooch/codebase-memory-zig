# Progress: Near-Parity Graph Exactness

## 2026-04-21

- Moved the plan into active execution and re-audited the graph rows that were
  still described as "near parity" without exact fixture proof.
- Confirmed that Zig already persisted several rows the old plan was treating
  as hypothetical or incomplete:
  - `IMPORTS`
  - `SIMILAR_TO`
  - `FILE_CHANGES_WITH`
  - `TESTS` / `TESTS_FILE`
  - `CONFIGURES`
  - route-linked `DATA_FLOWS`
  - `THROWS` / `RAISES`
- Kept the real latest-upstream message-vocabulary delta explicit instead of
  widening scope during this slice:
  - upstream `Channel` / `LISTENS_ON`
  - Zig `EventTopic` / `EMITS` / `SUBSCRIBES`
- Extended `scripts/run_interop_alignment.sh` with per-fixture runtime setup so
  seeded git-history fixtures can be built as temporary repos during zig-only,
  golden-refresh, and full-compare runs.
- Tightened existing fixture contracts onto exact graph rows for:
  - `TESTS`
  - `TESTS_FILE`
  - shared `IMPORTS`
  - `CONFIGURES`
  - `USES_TYPE`
  - route-linked `DATA_FLOWS`
  - `THROWS`
  - `RAISES`
- Added `history-similarity-parity`, a seeded three-commit fixture that proves:
  - `SIMILAR_TO` row shape plus `jaccard` / `same_file`
  - `FILE_CHANGES_WITH` row shape plus `co_changes` / `coupling_score`
- The new exact fixture exposed one real implementation gap:
  `query_graph` dropped decimal edge-property values because
  `src/cypher.zig` only projected string, integer, and boolean JSON property
  types.
- Fixed that gap by preserving JSON numeric lexemes in edge-property
  projection, then added a direct regression test in `src/cypher.zig` for
  decimal `SIMILAR_TO` and `FILE_CHANGES_WITH` property access.
- Reclassified the docs using the measured graph-exactness evidence:
  - `IMPORTS` is now treated as a verified shared graph row instead of a
    missing contract.
  - `SIMILAR_TO` and `FILE_CHANGES_WITH` now cite exact seeded-fixture proof.
  - the route/message row stays `Partial` because latest-upstream channel
    vocabulary still differs.
- Final verification for this plan:
  - `zig fmt src/cypher.zig`: pass
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/run_interop_alignment.sh --update-golden`: pass (`39/39`)
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`39/39`)
  - `bash scripts/run_interop_alignment.sh`: pass with `39` fixtures, `301`
    comparisons, `164` strict matches, `45` diagnostic-only comparisons, `0`
    mismatches, and `cli_progress: match`
