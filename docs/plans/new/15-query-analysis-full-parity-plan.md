# Plan: Near-Parity Query Analysis Contracts

## Goal
Promote or downgrade the query and analysis tool rows using exact contract
fixtures instead of bounded assertions.

## Current Phase
Pending

## File Map
- Modify: `src/mcp.zig`
- Modify: `src/query_router.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/golden/architecture-aspects-parity.json`
- Create: `testdata/interop/golden/search-code-ranking-parity.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`

## Phases

### Phase 1: Tighten exactness targets
- [ ] Enumerate the exact rows in this plan: `query_graph`,
      `trace_call_path`, `get_code_snippet`, `get_graph_schema`,
      `get_architecture`, `search_code`, `list_projects`, `delete_project`,
      `index_status`, and `manage_adr`.
- [ ] For each row, record whether full parity means exact payload identity,
      canonicalized equivalence, or a deliberate downgrade.
- **Status:** pending

### Phase 2: Expand fixtures for exact contract coverage
- [ ] Add `query_graph` fixtures for boolean precedence, multi-column ordering,
      path syntax, distinct/count combinations, and numeric predicates.
- [ ] Add exact response-shape fixtures for `trace_call_path`, including mode
      defaults, `risk_labels`, `include_tests`, and alias handling.
- [ ] Add snippet fixtures for ambiguity suggestions, suffix fallback,
      `include_neighbors`, and source-line behavior.
- [ ] Add architecture fixtures that explicitly assert every supported aspect.
- [ ] Add search-code fixtures that lock ranking order, deduplication, mode
      behavior, snippet context, and regex/plain-text handling.
- **Status:** pending

### Phase 3: Fix mismatches revealed by exact fixtures
- [ ] Update `src/mcp.zig` and `src/query_router.zig` only where the exact
      fixture results expose a real behavioral delta.
- [ ] Keep any canonicalization in `scripts/run_interop_alignment.sh` limited
      to representation differences that do not change user-visible meaning.
- **Status:** pending

### Phase 4: Reclassify query and analysis rows
- [ ] Promote rows with exact behavior and exact fixtures.
- [ ] Downgrade rows that still depend on narrower Zig semantics or
      implementation-specific ranking choices.
- **Status:** pending

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Use exact fixtures before code edits | Several current rows may already be full on behavior but only lack proof. |
| Allow canonicalization only for representation noise | The point of this plan is contract exactness, not lenient comparison. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
