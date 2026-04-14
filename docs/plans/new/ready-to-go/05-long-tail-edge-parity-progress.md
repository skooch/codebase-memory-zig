# Long-Tail Edge Parity Progress

## Scope

Targeted long-tail edge families not already covered by the verified shared-capability parity surface.

### In scope (implemented)

| Edge family | Source node | Target node | Languages | Classification |
|-------------|------------|-------------|-----------|----------------|
| `WRITES` | Function/Module | Variable | Python, JS/TS/TSX, Rust, Zig | Assignment LHS resolved via registry |
| `THROWS` | Function/Module | Exception type | JS/TS/TSX | Throw statement; exception name does NOT contain "Error"/"Panic" |
| `RAISES` | Function/Module | Exception type | JS/TS/TSX | Throw statement; exception name contains "Error"/"Panic"/"error"/"panic" |

### Out of scope (with rationale)

| Edge family | Rationale |
|-------------|-----------|
| `OVERRIDE` | Go-only in the C implementation; Go is not a target language in the Zig port |
| `CONTAINS_PACKAGE` | Never actually implemented in C codebase (documented but no creation code) |
| `HANDLES` | Part of the deferred route-graph system |
| `DATA_FLOWS` | Part of the deferred route-graph system |
| `READS` | C implementation only extracts WRITES from assignments, not READS |

## Fixtures

- `testdata/interop/edge-parity/writes_app.py` — Python module with class, functions, and module-level variable assignment
- `testdata/interop/edge-parity/throws_app.js` — JavaScript module with custom error class and throw statements

## Fixture verification (end-to-end)

Verified by indexing the edge-parity fixture and querying via MCP:

```
Nodes: 14, Edges: 22

WRITES edges:
  update_config → WRITES → current_config
  writes_app.py → WRITES → current_config

RAISES edges:
  validate → RAISES → ValidationError

Functions: build_config, process, update_config, validate
Classes: Config, ValidationError
Variables: current_config
```

## Phases

### Phase 1: Lock the Edge-Breadth Contract
- [x] Researched original C edge families: WRITES, THROWS/RAISES, OVERRIDE, CONTAINS_PACKAGE
- [x] Determined OVERRIDE (Go-only) and CONTAINS_PACKAGE (never implemented) are out of scope
- [x] Created parity fixtures under `testdata/interop/edge-parity/`
- [x] Added manifest entry with query assertions using `r.type` (not `type(r)`)
- **Status:** complete

### Phase 2: Implement Additional Edge Families
- [x] Added `UnresolvedWrite` and `UnresolvedThrow` types to `src/extractor.zig`
- [x] Implemented `assignmentLhs()` for WRITES extraction across all target languages
- [x] Implemented `parseThrowException()` for THROWS/RAISES extraction (JS/TS/TSX)
- [x] Wired extraction into `extractFile()` main loop
- [x] Updated `finishExtraction()` and `freeFileExtraction()` with proper lifecycle management
- [x] Added resolution to `resolveExtractions()` in `src/pipeline.zig`
- [x] Added unit tests for extraction functions (30+ assertions)
- [x] Added store persistence tests for WRITES, THROWS, and RAISES edges
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] `zig build` passes
- [x] `zig build test` passes (all unit + store tests green)
- [x] End-to-end fixture verification confirms WRITES and RAISES edges are created
- [x] Update `docs/port-comparison.md` — split "Richer long-tail edge families" into `WRITES/THROWS/RAISES` (Near parity) and "Remaining" (Partial with rationale)
- [x] Update `docs/gap-analysis.md` — added Plan 05 completion entry, updated shared-capability table, updated deferred metadata section
- **Status:** complete
