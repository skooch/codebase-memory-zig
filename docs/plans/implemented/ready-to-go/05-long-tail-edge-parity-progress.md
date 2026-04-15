# Long-Tail Edge Parity Progress

## Scope

Targeted long-tail edge families not already covered by the verified shared-capability parity surface.

Controlled Zig-vs-C interop on 2026-04-15 showed that the current C reference
does not emit `WRITES` rows for the edge-parity fixture, so `WRITES` is not
classified as original-project parity in this plan.

### In scope (implemented)

| Edge family | Source node | Target node | Languages | Classification |
|-------------|------------|-------------|-----------|----------------|
| `THROWS` | Function/Module | Exception type | JS/TS/TSX | Throw statement; exception name does NOT contain "Error"/"Panic" |
| `RAISES` | Function/Module | Exception type | JS/TS/TSX | Throw statement; exception name contains "Error"/"Panic"/"error"/"panic" |

### Out of scope (with rationale)

| Edge family | Rationale |
|-------------|-----------|
| `OVERRIDE` | Go-only in the C implementation; Go is not a target language in the Zig port |
| `CONTAINS_PACKAGE` | Never actually implemented in C codebase (documented but no creation code) |
| `HANDLES` | Part of the deferred route-graph system |
| `DATA_FLOWS` | Part of the deferred route-graph system |
| `WRITES` | Current C reference did not emit WRITES on the parity fixture; keep out of parity claims until the original-overlap contract is proven |
| `READS` | Current C reference did not emit READS on the parity fixture |

## Fixtures

- `testdata/interop/edge-parity/throws_app.js` — JavaScript module with custom error class and throw statements

## Fixture verification (end-to-end)

Verified by indexing the edge-parity fixture and querying via MCP:

```
Nodes: 14, Edges: 22

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
- [x] Reclassified WRITES as not proven original-overlap after the full Zig-vs-C harness showed C returned no WRITES rows on the parity fixture
- **Status:** complete

### Phase 2: Implement Additional Edge Families
- [x] Added `UnresolvedThrow` extraction for the accepted parity slice
- [x] Implemented `parseThrowException()` for THROWS/RAISES extraction (JS/TS/TSX)
- [x] Wired extraction into `extractFile()` main loop
- [x] Updated `finishExtraction()` and `freeFileExtraction()` with proper lifecycle management
- [x] Added resolution to `resolveExtractions()` in `src/pipeline.zig`
- [x] Added unit tests for extraction functions (30+ assertions)
- [x] Added store persistence tests for THROWS and RAISES edges
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] `zig build` passes
- [x] `zig build test` passes (all unit + store tests green)
- [x] End-to-end fixture verification confirms RAISES edges are created
- [x] Update `docs/port-comparison.md` — split `THROWS`/`RAISES` from remaining long-tail edge families
- [x] Update `docs/gap-analysis.md` — added Plan 05 completion entry, updated shared-capability table, updated deferred metadata section
- **Status:** complete
