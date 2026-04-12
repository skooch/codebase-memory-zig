# Handoff: Plan 03 — Advanced Trace Parity

**Branch:** `feat/advanced-trace-parity`
**Worktree:** `../worktrees/advanced-trace-parity`
**Predecessor:** Plan 02 (Agent Ecosystem Installation) is implemented on `main`.

## Objective

Expand the Zig `trace_call_path` tool from call-edge-only BFS to match the C reference's richer trace surface: multiple edge-type filtering, trace modes (calls/data_flow/cross_service), hop-based risk classification, test-file filtering, richer response format with callers/callees separation and per-node metadata.

## What already exists in Zig

### MCP handler (`src/mcp.zig:394-428`)
- `handleTraceCallPath` accepts: `project`, `start_node_qn`, `direction` (in/out/both), `depth` (default 6)
- Calls `traverseEdgesBreadthFirst` with a single optional `edge_type` (currently always `null`)
- Returns flat `{"edges": [{"source": "qn", "target": "qn", "type": "edge_type"}, ...]}` format
- Tool schema in `tools/list`: `{"name":"trace_call_path","description":"Trace CALLS edges between nodes","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"start_node_qn":{"type":"string"},"direction":{"type":"string","enum":["in","out","both"]},"depth":{"type":"number"}}}}`

### Store BFS (`src/store.zig:1322-1393`)
- `traverseEdgesBreadthFirst(project, start_node_id, direction, max_depth, edge_type)` — `edge_type` is a single optional string
- Uses batch queries (`findEdgesBySourceBatch`, `findEdgesByTargetBatch`) to process entire frontier levels
- Tracks visited nodes and seen edges to prevent cycles
- Returns `[]TraversalEdge` with `depth` annotation on each edge
- `TraversalEdge` struct: `{id, project, source_id, target_id, edge_type, properties_json, depth}`

### Existing tests
- `src/store_test.zig:1774-1845` — BFS test with outbound/inbound/both, edge type filter, depth verification
- `src/mcp.zig:1071-1111` — end-to-end trace test via JSON-RPC
- Interop fixtures: all golden files include `trace_call_path` assertions with `[source_name, target_name, edge_type]` triples

### Known contract differences from C
- Zig uses `start_node_qn` (qualified name); C uses `function_name` (bare name lookup)
- Zig returns `{"edges": [...]}` flat; C returns `{"function":"...", "direction":"...", "mode":"...", "callees":[...], "callers":[...]}`
- Zig does not have modes, risk labels, edge type arrays, include_tests, or max_results

## What the C reference does (delta to implement)

### 1. Trace modes (`resolve_trace_edge_types`)
Three mode presets, each mapping to different edge type sets:
- **calls** (default): `["CALLS"]`
- **data_flow**: `["CALLS", "DATA_FLOWS"]`
- **cross_service**: `["HTTP_CALLS", "ASYNC_CALLS", "DATA_FLOWS", "CALLS"]`

Additionally, an explicit `edge_types` array parameter overrides mode defaults.
Priority: explicit edge_types > mode-based defaults > hardcoded fallback.

### 2. Multiple edge type filtering
The BFS in C accepts an array of edge types (up to 16), not just one. The SQL becomes `AND type IN (?, ?, ...)` instead of `AND type = ?`.

### 3. Risk classification (`cbm_hop_to_risk`)
Hop-distance-based risk labels applied to each visited node:
- Hop 1 = `CRITICAL`
- Hop 2 = `HIGH`
- Hop 3 = `MEDIUM`
- Hop 4+ = `LOW`

Enabled by `risk_labels: true` parameter in the tool call.

### 4. Test file filtering (`is_test_file`)
Heuristic path matching: marks files as test if path contains `/test`, `test_`, `_test.`, `/tests/`, `/spec/`, `.test.`
- `include_tests=false` (default): test-file nodes are excluded from traversal results
- `include_tests=true`: included with `is_test: true` marker

### 5. Impact summary (`cbm_build_impact_summary`)
Counts nodes by risk tier (critical/high/medium/low), flags `has_cross_service`. This is an optional analysis layer, not always included in output.

### 6. Richer response format
C returns per-node objects with hop distance and optional metadata:
```json
{
  "function": "main",
  "direction": "both",
  "mode": "calls",
  "callees": [
    {"name": "helper", "qualified_name": "pkg.helper", "hop": 1, "risk": "CRITICAL", "is_test": false}
  ],
  "callers": [
    {"name": "entry", "qualified_name": "pkg.entry", "hop": 1, "risk": "CRITICAL"}
  ]
}
```

### 7. Max results limit
C caps at 100 visited nodes per direction.

## Implementation approach

### Phase 1: Store BFS — multi-edge-type support

**File: `src/store.zig`**

1. Change `traverseEdgesBreadthFirst` signature: replace `edge_type: ?[]const u8` with `edge_types: ?[]const []const u8` (slice of type strings).
2. Update `findEdgesBatch` to build `AND type IN (?, ?, ...)` when multiple types given, single `AND type = ?` when one type, no filter when null.
3. Add `max_results: ?u32` parameter to cap total visited nodes (default: null = unlimited, but the MCP handler should pass 100).
4. **Keep `TraversalEdge` struct as-is** — the depth annotation is already there.
5. Update `src/store_test.zig` BFS test to exercise multi-type filtering.

### Phase 2: MCP handler — modes, risk, include_tests, response format

**File: `src/mcp.zig`**

1. Add new parameters to `handleTraceCallPath`:
   - `mode` (string, default "calls") — maps to edge type sets
   - `edge_types` (JSON array of strings, optional) — overrides mode
   - `risk_labels` (bool, default false) — include hop-based risk classification
   - `include_tests` (bool, default true) — whether to include test-file nodes
   - Keep `function_name` as an alias for `start_node_qn` for C compatibility (try `start_node_qn` first, fall back to `function_name`)

2. Add mode resolution function:
   ```
   fn resolveTraceEdgeTypes(mode, explicit_edge_types) -> [][]const u8
   ```

3. Add risk classification:
   ```
   fn hopToRisk(hop: u32) -> []const u8  // "CRITICAL", "HIGH", "MEDIUM", "LOW"
   ```

4. Add test file detection:
   ```
   fn isTestFile(file_path: []const u8) -> bool  // heuristic path matching
   ```

5. Change response format from flat edges to structured callers/callees:
   - For direction "both", run outbound then inbound separately (as C does)
   - Each result node includes: `name`, `qualified_name`, `hop`, and optionally `risk` and `is_test`
   - Top-level: `{"function": "...", "direction": "...", "mode": "...", "callees": [...], "callers": [...]}`

6. Update `tools/list` schema to advertise new parameters.

### Phase 3: Interop fixtures

1. Add `testdata/interop/trace-parity/` fixture directory with Python/JS/TS source files that exercise:
   - Multi-hop traversal with CALLS edges
   - Mixed edge types (CALLS + USAGE)
   - Test file filtering (files with `test_` prefix)
2. Add fixture entries to `testdata/interop/manifest.json` with trace-specific assertions.
3. Update existing golden files if the response format changes (the interop harness normalizes trace output — check `scripts/run_interop_alignment.sh` for the trace comparison logic).

### Phase 4: Unit tests and doc updates

1. Extend `src/store_test.zig` with multi-edge-type BFS test
2. Extend `src/mcp.zig` trace test with new parameters (mode, risk_labels, include_tests)
3. Update `docs/port-comparison.md` trace row from `Partial` to `Near parity`
4. Update `docs/gap-analysis.md` to reflect the completed trace surface

## IMPORTANT: Response format backward compatibility

The current interop harness (golden files) expects trace results as `[source_name, target_name, edge_type]` triples. The harness script normalizes the raw MCP output into this format. Before changing the response format:

1. Read `scripts/run_interop_alignment.sh` trace normalization logic to understand how the harness converts MCP output to golden format.
2. Ensure the new response format still normalizes correctly OR update the harness normalization AND regenerate golden files.

The safest approach: keep the existing `{"edges": [...]}` format as the base and ADD the new structured fields alongside it, OR update the harness normalization to handle the new format.

## Key files to read before starting

| File | Why |
|------|-----|
| `src/mcp.zig:394-428` | Current trace handler — extend this |
| `src/store.zig:1177-1393` | BFS + batch edge queries — extend for multi-type |
| `src/store.zig:118-132` | TraversalEdge/TraversalDirection structs |
| `src/store_test.zig:1774-1845` | Existing BFS tests — add multi-type tests |
| `scripts/run_interop_alignment.sh` | Trace normalization — must stay compatible |
| `testdata/interop/manifest.json` | Fixture assertions — extend for new trace fixtures |

## Verification checklist

- [ ] `zig build` succeeds
- [ ] `zig build test` passes (all existing + new trace tests)
- [ ] `bash scripts/run_interop_alignment.sh` reports 0 mismatches (existing fixtures still pass)
- [ ] New trace-parity fixture in manifest exercises multi-type and risk features
- [ ] `docs/port-comparison.md` trace row updated

## Gotchas

- **Do not break existing golden files.** The interop harness is the primary regression gate. If you change the trace response format, update the harness normalization to handle it.
- **The C reference's `function_name` is a bare name lookup**, not a qualified name. Adding `function_name` as an alias for `start_node_qn` means the handler needs a name-based node lookup fallback (the store has `findNodeByName` or similar).
- **The `data_flow` and `cross_service` modes reference edge types (`DATA_FLOWS`, `HTTP_CALLS`, `ASYNC_CALLS`) that the Zig extractor may not currently produce.** This is fine — the modes should still be accepted and work correctly if those edges ever appear. Don't stub them out.
- **Keep Python 3.9 compatibility** in any inline Python in the interop harness (no `X | Y` type union syntax).
- **`edge_types` parameter conflicts** — if both `mode` and `edge_types` are provided, `edge_types` wins. Document this in the tool schema description.
