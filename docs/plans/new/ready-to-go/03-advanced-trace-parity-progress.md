# Plan 03: Advanced Trace Parity — Progress

**Branch:** `feat/advanced-trace-parity`
**Status:** Complete
**Date:** 2026-04-12

## Completed Work

### Phase 1: Store BFS multi-edge-type support
- Changed `traverseEdgesBreadthFirst` signature from `edge_type: ?[]const u8` to `edge_types: ?[]const []const u8`
- Updated `findEdgesBatch` to build `AND type IN (?, ?, ...)` for multiple types, single `AND type = ?` for one type, no filter for null
- Added `max_results: ?u32` parameter to cap visited nodes during BFS traversal
- Updated all callers: `mcp.zig`, `query_router.zig`, `store_test.zig`
- Added unit tests for multi-edge-type filtering and max_results cap

### Phase 2: MCP handler enhancements
- Added `mode` parameter (calls/data_flow/cross_service) with edge type presets
- Added `edge_types` explicit override array (takes priority over mode)
- Added `risk_labels` parameter for hop-based risk classification (CRITICAL/HIGH/MEDIUM/LOW)
- Added `include_tests` parameter for test-file node filtering
- Added `function_name` as alias for `start_node_qn` (C compat) with name-based search fallback
- Added helper functions: `resolveTraceEdgeTypes`, `hopToRisk`, `isTestFile`, `stringArrayArg`
- Changed response format to structured `{"function", "direction", "mode", "edges", "callees", "callers"}`
- Updated `tools/list` schema to advertise all new parameters
- Added comprehensive tests for all new parameters

### Phase 3: Interop backward compatibility
- Included flat `edges` array alongside structured `callees`/`callers` in response
- Set edge type filter to null (all types) when neither `mode` nor `edge_types` is explicitly passed
- Verified all 11 interop golden fixtures pass (Golden comparison: 11/11)

### Phase 4: Documentation
- Updated `docs/port-comparison.md` trace row from `Partial` to `Near parity`
- Updated trace tool contract differences to reflect `function_name` alias and mode support
- Updated `docs/gap-analysis.md` traversal section, trace tool row, and deferred slices

## Verification

- [x] `zig build` succeeds
- [x] `zig build test` passes (all existing + new trace tests)
- [x] `bash scripts/run_interop_alignment.sh --zig-only` reports 11/11 passed, 0 mismatches
- [x] `docs/port-comparison.md` trace row updated
- [x] Progress file written

## Key Design Decisions

1. **Backward-compatible response format**: The handler emits both the flat `edges` array (for interop harness compatibility) and the structured `callees`/`callers` arrays. The interop harness's `canonical_trace` function checks for `edges` first, so existing golden files continue to work.

2. **Null edge filter default**: When neither `mode` nor `edge_types` is explicitly provided, the BFS uses null (no type filter), preserving the original all-edges traversal behavior. Only explicit `mode` or `edge_types` parameters trigger type filtering.

3. **Priority chain**: explicit `edge_types` > `mode`-based defaults > null (all edges).

4. **function_name fallback**: The handler tries `start_node_qn` first (qualified name lookup), then `function_name` via both qualified name and name-based search for C compatibility.
