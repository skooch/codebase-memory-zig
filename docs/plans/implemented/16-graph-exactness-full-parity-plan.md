# Plan: Near-Parity Graph Exactness

## Goal
Promote or downgrade the near-parity graph and pipeline rows using exact graph
fixtures and explicit vocabulary decisions.

## Current Phase
Completed

## File Map
- Modify: `src/cypher.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/graph-exactness-history-similarity/`
- Create: `testdata/interop/golden/history-similarity-parity.json`
- Modify: `testdata/interop/golden/*.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`

## Phases

### Phase 1: Decide the graph-vocabulary targets
- [x] Keep `moderate` indexing scoped to the tool-surface row; it does not
      block promotion of unrelated graph rows.
- [x] Treat Zig `IMPORTS` as already implemented and require exact fixture proof
      before promotion instead of leaving the row partial by assumption.
- [x] Keep the latest-upstream `Channel` / `LISTENS_ON` vocabulary as a real
      remaining gap; do not fake parity over Zig `EventTopic` /
      `EMITS` / `SUBSCRIBES`.
- **Status:** completed

### Phase 2: Add exact graph fixtures
- [x] Tighten the existing shared fixtures onto exact graph rows for `TESTS`,
      `TESTS_FILE`, `CONFIGURES`, `USES_TYPE`, route-linked `DATA_FLOWS`,
      `THROWS`, `RAISES`, and shared `IMPORTS`.
- [x] Add a seeded runtime fixture for exact `SIMILAR_TO` and
      `FILE_CHANGES_WITH` rows plus edge-property projection.
- [x] Leave channel/message rows below full parity because the public
      vocabulary still differs from latest upstream.
- **Status:** completed

### Phase 3: Implement only the selected graph deltas
- [x] Extend the interop harness with per-fixture runtime setup so seeded git
      history can be compared end to end.
- [x] Fix the real exactness delta exposed by the new fixture:
      `query_graph` now preserves decimal edge-property values instead of
      dropping them.
- [x] Keep the message-vocabulary difference explicit instead of widening the
      implementation surface during this slice.
- **Status:** completed

### Phase 4: Reclassify graph rows
- [x] Promote the shared `IMPORTS` row now that persisted import edges are
      exact-compared on the parity fixtures.
- [x] Re-state the near-parity graph rows in terms of exact fixture evidence:
      `TESTS`, `CONFIGURES`, `USES_TYPE`, route-linked `DATA_FLOWS`,
      `THROWS`/`RAISES`, `SIMILAR_TO`, and `FILE_CHANGES_WITH`.
- [x] Keep the route/message row partial because latest-upstream `Channel` /
      `LISTENS_ON` still differs from Zig `EventTopic` / `SUBSCRIBES`.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Do not let `moderate` mode block unrelated graph promotions | The graph rows in this slice can be scored honestly without pretending tool-surface parity. |
| Treat `IMPORTS` as implemented-but-unproven until exact fixtures pass | The source already persists `IMPORTS`; the missing piece was measured proof, not a new graph pass. |
| Keep latest-upstream channel vocabulary as an explicit remaining gap | Zig still exposes `EventTopic` / `EMITS` / `SUBSCRIBES`, which is not the same contract as `Channel` / `LISTENS_ON`. |
| Use exact graph fixtures for promotion | These rows should only move when the stored graph is measurably equivalent. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
