# Progress: Moderate Index Mode Parity

## 2026-04-21

- Started the `moderate` mode slice in
  `docs/plans/in-progress/20-moderate-index-mode-parity-plan.md`.
- Confirmed the current Zig port still exposes only `full` and `fast` at the
  public MCP surface:
  - `src/mcp.zig` advertises only `full` / `fast` and rejects `moderate`
  - the tool-surface interop fixture still encodes the old
    `Unsupported index_repository mode` contract
- Confirmed the released upstream `v0.6.0` contract advertises:
  - `full`: all passes including semantic edges
  - `moderate`: fast discovery + `SIMILAR_TO` + `SEMANTICALLY_RELATED`
  - `fast`: structure only
- Confirmed the current Zig internals do not have a meaningful mode split
  beyond discovery skips:
  - `src/discover.zig` only distinguishes `.fast` for a small skip list
  - `src/pipeline.zig` still runs the same enrichment passes after discovery in
    both current modes
- Implemented the public and internal mode split:
  - `src/pipeline.zig` now defines explicit `fast` / `moderate` / `full`
    profiles
  - `fast` uses fast discovery and skips optional enrichment passes
  - `moderate` uses fast discovery but retains the current enrichment passes
  - `full` uses full discovery plus the current enrichment passes
- Updated the public MCP contract in `src/mcp.zig`:
  - `tools/list` now advertises `index_repository.mode` as
    `full` / `moderate` / `fast`
  - `tools/call` now accepts `mode=\"moderate\"`
- Added focused verification for the new split:
  - `src/mcp.zig` now has a direct `index_repository accepts moderate mode`
    test
  - `src/pipeline.zig` now proves `fast` skips `SIMILAR_TO` while `moderate`
    still produces it on a duplicate-code fixture
- Updated the interop surface:
  - `testdata/interop/manifest.json` and the generated goldens now encode
    accepted `moderate` mode instead of the old unsupported-mode error
  - `tool-surface-parity` now keeps the latest-upstream search-surface delta
    diagnostic-only while proving the accepted Zig-side `moderate` contract
- Hit one harness regression during full compare:
  - `protocol-contract` initially reopened as a strict mismatch because the
    stale local C comparator still advertises only `full` / `fast`
  - fixed by teaching `scripts/run_interop_alignment.sh` to snapshot only the
    schema fields each contract fixture explicitly requests
  - after that fix, `protocol-contract` returned to a strict shared match and
    `tool-surface-parity` remained the only deliberate diagnostic tool-surface
    row
- Final verification for this slice:
  - `zig build`
  - `zig build test`
  - `bash scripts/run_interop_alignment.sh --update-golden`
  - `bash scripts/run_interop_alignment.sh --zig-only` -> `39/39` passed
  - `bash scripts/run_interop_alignment.sh` -> `39` fixtures, `301`
    comparisons, `164` strict matches, `45` diagnostic-only comparisons, `0`
    mismatches, `cli_progress: match`
- Final doc outcome:
  - `docs/port-comparison.md` and `docs/gap-analysis.md` no longer list
    `index_repository.mode` as an active latest-upstream gap
  - the remaining latest-upstream backlog after this slice is
    `search_graph.semantic_query`, `SEMANTICALLY_RELATED`, and the `Channel` /
    `LISTENS_ON` graph vocabulary
