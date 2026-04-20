# Plan: Near-Parity Graph Exactness

## Goal
Promote or downgrade the near-parity graph and pipeline rows using exact graph
fixtures and explicit vocabulary decisions.

## Current Phase
Pending

## File Map
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/discover.zig`
- Modify: `src/route_nodes.zig`
- Modify: `src/semantic_links.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/golden/imports-parity.json`
- Create: `testdata/interop/golden/channel-parity.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`

## Phases

### Phase 1: Decide the graph-vocabulary targets
- [ ] Decide whether `moderate` indexing must land before any affected row can
      be promoted.
- [ ] Decide whether Zig should persist `IMPORTS` as a first-class edge family
      or whether every dependent row should stay below full parity.
- [ ] Decide whether to adopt upstream `Channel` / `LISTENS_ON` exactly or to
      keep Zig `EventTopic` / `SUBSCRIBES` and downgrade the affected row.
- **Status:** pending

### Phase 2: Add exact graph fixtures
- [ ] Add graph fixtures for exact `TESTS`, `CONFIGURES`, `FILE_CHANGES_WITH`,
      `USES_TYPE`, `THROWS`, `RAISES`, route-linked `DATA_FLOWS`, and
      `SIMILAR_TO` payloads.
- [ ] Add exact `IMPORTS` fixture coverage if `IMPORTS` is adopted.
- [ ] Add exact channel/message fixture coverage if channel vocabulary parity is
      adopted.
- **Status:** pending

### Phase 3: Implement only the selected graph deltas
- [ ] Update `src/pipeline.zig`, `src/store.zig`, `src/discover.zig`,
      `src/route_nodes.zig`, and `src/semantic_links.zig` only for the
      vocabulary and behavior deltas selected in Phase 1.
- [ ] Keep already-green bounded rows unchanged unless exact fixtures reveal a
      real divergence.
- **Status:** pending

### Phase 4: Reclassify graph rows
- [ ] Promote rows with exact graph behavior and exact fixtures.
- [ ] Downgrade rows that still depend on different vocabulary, missing edges,
      or bounded graph slices.
- **Status:** pending

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Make vocabulary choices explicit before coding | `IMPORTS` and `Channel` parity change the public graph contract, not just tests. |
| Use exact graph fixtures for promotion | These rows should only move when the stored graph is measurably equivalent. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
