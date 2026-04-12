# Interop Testing Review

**Date:** 2026-04-12
**Scope:** Focused review of the interop/parity testing infrastructure
**Method:** Multi-pass (map -> deep -> saturation -> synthesis)
**Status:** Complete

---

## 1. Subsystem Map

### Test Harness Scripts

| Script | Lines | Purpose |
|--------|-------|---------|
| `scripts/run_interop_alignment.sh` | 1,729 | MCP protocol comparison: Zig vs C or Zig vs golden snapshots |
| `scripts/run_cli_parity.sh` | 344 | CLI install/uninstall/update lifecycle comparison |
| `scripts/test_runtime_lifecycle.sh` | ~85 | Process lifecycle signal handling (not interop) |

### Fixtures (testdata/interop/)

| Fixture | Language | Type | Manifest | Golden |
|---------|----------|------|----------|--------|
| test-tagging | Python | basic | yes | yes |
| adr-parity | Python | parity | yes | yes |
| python-basic | Python | basic | yes | yes |
| python-parity | Python | parity | yes | yes |
| javascript-basic | JavaScript | basic | yes | yes |
| javascript-parity | JavaScript | parity | yes | yes |
| typescript-basic | TypeScript | basic | yes | yes |
| typescript-parity | TypeScript | parity | yes | yes |
| rust-basic | Rust | basic | yes | yes |
| rust-parity | Rust | parity | yes | yes |
| zig-basic | Zig | basic | yes | yes |
| **scip** | **TypeScript** | **SCIP overlay** | **NO** | **NO** |

### CI Integration

| Workflow | Trigger | Mode | Failure behavior |
|----------|---------|------|-----------------|
| `ci.yml` (per-push) | push/PR | `--zig-only` golden snapshot | Blocks merge |
| `interop-nightly.yml` (weekly) | Mon 04:17 UTC | Full Zig-vs-C compare | **`continue-on-error: true`** -- silent |

### MCP Tool Coverage

13 tools exposed by the Zig server (from `SHARED_TOOL_NAMES`):

| Tool | tools/list check | Manifest assertions | Golden snapshot |
|------|:---:|:---:|:---:|
| `index_repository` | yes | yes (all fixtures) | yes (min thresholds) |
| `search_graph` | yes | yes (10 fixtures) | yes (full nodes) |
| `query_graph` | yes | yes (8 fixtures) | yes (columns + rows) |
| `trace_call_path` | yes | yes (8 fixtures) | yes (edge lists) |
| `get_architecture` | yes | yes (3 fixtures) | yes |
| `search_code` | yes | yes (3 fixtures) | yes |
| `detect_changes` | yes | yes (3 fixtures) | **count only** |
| `manage_adr` | yes | yes (1 fixture) | yes |
| `list_projects` | yes | yes (all fixtures) | yes (names only) |
| **`get_code_snippet`** | **yes** | **NO** | **NO** |
| **`get_graph_schema`** | **yes** | **NO** | **NO** |
| **`index_status`** | **yes** | **NO** | **NO** |
| **`delete_project`** | **yes** | **NO** | **NO** |

---

## 2. Issue Register

### I1: Four MCP tools have zero interop assertion coverage
- **Area:** Manifest / fixture design
- **Status:** validated
- **Severity:** high
- **Evidence:** `get_code_snippet`, `get_graph_schema`, `index_status`, and `delete_project` appear in `SHARED_TOOL_NAMES` (line 76-90 of the alignment script) and are verified to exist at `tools/list` level. But no fixture in `manifest.json` ever calls them with assertions. These tools could regress entirely without detection. The Zig server does have unit tests for them in `src/mcp.zig` (lines 1162-1213, 1453-1480), but the interop harness never exercises them.
- **Why it matters:** `get_code_snippet` is a primary user-facing tool. `delete_project` affects state. Schema/status are less critical but still untested.
- **Remediation:** Add assertions in at least one parity fixture per tool. `python-parity` is the best candidate (most comprehensive).

### I2: SCIP fixture is orphaned
- **Area:** Fixtures
- **Status:** validated
- **Severity:** medium
- **Evidence:** `testdata/interop/scip/` exists with `src/main.ts` and `.codebase-memory/scip.json` (a valid SCIP symbol overlay). There is no corresponding entry in `manifest.json`. The SCIP ingestion path (`src/scip.zig`) is never exercised in interop testing.
- **Why it matters:** SCIP overlay import is a supported feature (mapped in `src/scip.zig`, 236 lines). Regressions in SCIP parsing or symbol merging would be invisible.
- **Remediation:** Add a `scip` fixture entry to `manifest.json` with assertions validating that SCIP-provided symbols appear in the graph alongside tree-sitter-extracted symbols.

### I3: `detect_changes` assertions are all vacuous
- **Area:** Manifest assertions
- **Status:** validated
- **Severity:** medium
- **Evidence:** All three parity fixtures with `detect_changes` use `{"expect": {}}` (lines 791-793, 1012-1019, 1264-1271 of manifest.json). The golden snapshot stores only `detect_changes_count` (call count), not the actual response content. The canonical comparison function `compare_golden_snapshot` explicitly skips content: "only compare call count (output is git-state-dependent)" (line 1101).
- **Why it matters:** `detect_changes` could return completely wrong data (wrong files, wrong symbols) and both the assertion check and golden comparison would pass.
- **Remediation:** At minimum, assert `changed_count` and that the response has the expected shape (contains `changed_files` and `impacted_symbols` keys). For fixtures with no changes, assert `changed_count: 0`.

### I4: Nightly full-comparison failures are invisible
- **Area:** CI
- **Status:** validated
- **Severity:** high
- **Evidence:** `interop-nightly.yml` lines 51 and 57 both have `continue-on-error: true`. The workflow always succeeds regardless of comparison results. Reports are uploaded as artifacts (30-day retention) but no notification is triggered.
- **Why it matters:** The entire point of the nightly comparison is to catch Zig/C divergence. With `continue-on-error: true`, divergence is silently recorded but never surfaced.
- **Remediation:** Two options:
  1. Remove `continue-on-error: true` so the workflow fails on mismatch (requires the comparison to be clean enough to not false-positive).
  2. Keep `continue-on-error` but add a step that parses the report JSON and posts a summary to an issue or notification channel.

### I5: Progress phase validation is incomplete
- **Area:** Alignment harness
- **Status:** validated
- **Severity:** low
- **Evidence:** `SHARED_PROGRESS_PHASES` (line 92-102) checks [1/9], [2/9], [3/9], [4/9], [9/9] but the Zig server emits [5/9] "Detecting tests", [7/9] "Analyzing git history", [8/9] "Linking config files" (`src/main.zig:364-366`). There is no [6/9] phase at all. The harness `canonical_progress_lines` function (line 551-565) explicitly skips [5/9]-[8/9].
- **Why it matters:** Progress phase changes (renaming, reordering, adding/removing) would not be detected.
- **Remediation:** Update `SHARED_PROGRESS_PHASES` to include [5/9], [7/9], [8/9]. Document that [6/9] is intentionally absent.

### I6: No Go language fixture
- **Area:** Fixture coverage
- **Status:** validated
- **Severity:** medium
- **Evidence:** The C reference implementation supports Go. The Zig extractor supports Go (`src/extractor.zig`). No Go fixture exists in `testdata/interop/`. Current coverage: Python, JavaScript, TypeScript, Rust, Zig.
- **Why it matters:** Go is a commonly indexed language. Go-specific constructs (interfaces, goroutines, multiple return values, package-level functions) have no interop parity check.
- **Remediation:** Add `go-basic` and `go-parity` fixtures.

### I7: `query_graph` assertions often accept empty results
- **Area:** Manifest assertions
- **Status:** validated
- **Severity:** medium
- **Evidence:** Many `query_graph` assertions in parity fixtures only specify `columns` without `required_rows_min`. Examples from `python-parity`:
  - `MATCH (a)-[r:INHERITS]->(b) ...` -- no `required_rows_min` (line 610)
  - `MATCH (a)-[r:DECORATES]->(b) ...` -- no `required_rows_min` (line 623)
  - `MATCH (a)-[r:CONFIGURES]->(b) ...` -- no `required_rows_min` (line 640)
  - `MATCH (a)-[r:WRITES]->(b) ...` -- no `required_rows_min` (line 653)
  - `MATCH (a)-[r:USES_TYPE]->(b) ...` -- no `required_rows_min` (line 666)

  The `check_assertions` function (line 860-861) only validates `required_rows_min` when present. The golden snapshot comparison IS strict (compares actual rows), so golden-mode catches these. But assertion-level checks during `compare` mode let empty results through.
- **Why it matters:** In `compare` mode against the C binary, a Zig regression that returns zero rows for INHERITS/DECORATES/CONFIGURES/WRITES/USES_TYPE would only be caught if both implementations agree. If C also returns empty (e.g. the C side doesn't extract decorators either), the comparison passes silently.
- **Remediation:** Add `required_rows_min: 1` to every query assertion that is expected to return rows. The golden snapshots already have the ground truth.

### I8: `search_graph` parameter translation masks potential divergence
- **Area:** Alignment harness
- **Status:** validated
- **Severity:** low
- **Evidence:** `build_requests` (lines 641-668) translates `label` to `label_pattern` for Zig and keeps `label` for C. The two implementations receive semantically different queries. If Zig's `label_pattern` does regex matching while C's `label` does exact matching, the comparison would not detect the difference.
- **Why it matters:** The translation layer is necessary because the APIs differ, but it means the harness tests "both implementations return the expected symbols" rather than "both implementations match each other's behavior."
- **Remediation:** This is inherent to API differences and acceptable. Document the translation explicitly in the manifest or a README so future maintainers understand the comparison is assertion-level, not output-level, for `search_graph`.

### I9: Golden snapshot diff messages lack detail for some tools
- **Area:** Report quality
- **Status:** validated
- **Severity:** low
- **Evidence:** `compare_golden_snapshot` (lines 1009-1145) provides row-level diff detail for `query_graph` (added/removed rows) and set-level detail for `tools_list` (added/removed). But for `search_code`, `trace_call_path`, `get_architecture`, and `manage_adr`, the mismatch message is just `"search_code[0]: differs"` with no detail about what changed.
- **Why it matters:** When a golden snapshot comparison fails, developers need to know *what* changed without re-running the full harness manually.
- **Remediation:** Add diff detail (added/removed entries) for `search_code`, `trace_call_path`, and `get_architecture`, matching the pattern already used for `query_graph`.

### I10: No negative / error-path test cases
- **Area:** Fixture design
- **Status:** validated
- **Severity:** medium
- **Evidence:** All manifest fixtures test happy paths only. No assertions test:
  - Querying a non-existent project
  - Passing invalid Cypher syntax
  - Calling `search_graph` / `query_graph` before `index_repository`
  - `get_code_snippet` with a non-existent `qualified_name`
  - `delete_project` then re-querying
- **Why it matters:** Error handling divergence between C and Zig is invisible. The Zig server might return different error codes or shapes.
- **Remediation:** Add an `error-paths` fixture that exercises error responses. At minimum: invalid project, invalid Cypher, missing symbol.

### I11: No `zig-parity` fixture
- **Area:** Fixture coverage
- **Status:** validated
- **Severity:** low
- **Evidence:** There's a `zig-basic` fixture (5 nodes, 1 edge) with simple function/struct patterns. No `zig-parity` fixture exists to exercise deeper Zig-specific constructs: comptime, error unions, tagged unions, `switch` on enums, test blocks, `@import` chains, pub/private visibility.
- **Why it matters:** The Zig language extractor may have Zig-specific bugs that are invisible because the basic fixture is too simple.
- **Remediation:** Add a `zig-parity` fixture with richer Zig code patterns.

### I12: `index_repository` golden comparison uses threshold, not actual counts
- **Area:** Golden snapshots
- **Status:** validated
- **Severity:** low
- **Evidence:** `build_golden_snapshot` (lines 999-1004) stores `nodes_min` and `edges_min` from the manifest assertions, not the actual node/edge counts from the Zig output. `compare_golden_snapshot` (lines 1132-1143) checks the Zig output meets these minimums. A regression from 20 nodes to 8 nodes would be invisible if the threshold is 7.
- **Why it matters:** Gradual extraction quality regression within the threshold range is undetectable.
- **Remediation:** Store actual counts in the golden snapshot (alongside thresholds) and alert if the count drops by more than a tolerance percentage.

### I13: `run_cli_parity.sh` permissions inconsistency
- **Area:** Scripts
- **Status:** validated
- **Severity:** trivial
- **Evidence:** `run_cli_parity.sh` is 644 (not executable). `run_interop_alignment.sh` is 755 (executable). CI invokes both via `bash scripts/...` so it works, but it's inconsistent.
- **Remediation:** `chmod +x scripts/run_cli_parity.sh`.

---

## 3. Themes

### T1: Presence-checked but not behavior-tested

Four out of 13 MCP tools (31%) are verified to exist at `tools/list` level but never exercised with actual requests. The harness has the infrastructure to test them (I1). The SCIP fixture has the test data but isn't wired in (I2). The gap is manifest entries, not harness capability.

### T2: Assertion looseness masked by golden strictness

The manifest assertions are intentionally loose (check names exist, columns match, edge types present). The golden snapshot comparison is much stricter (exact row matching). This two-tier design is reasonable, but the loose tier creates a false floor: in `compare` mode without golden snapshots, many regressions would pass. Several assertions could be tightened without losing flexibility (I3, I7).

### T3: CI gating asymmetry

Per-push CI gates golden snapshot checks (hard fail). Weekly full comparison is informational only (I4). This means the golden snapshots are the only real regression gate. If a golden snapshot is updated to accommodate a Zig change that diverges from C, there's no CI gate to catch the divergence until someone manually checks the nightly report artifact.

### T4: Happy-path-only fixture design

All 11 manifest fixtures test successful indexing and querying (I10). No fixture tests error paths, edge cases, or state transitions (delete then re-query). Error handling parity is invisible.

---

## 4. Validated Concern Matrix

| Concern | Status | Evidence |
|---------|--------|----------|
| Tools with zero interop coverage | **Confirmed** | 4/13 tools (31%) have no assertions |
| SCIP fixture orphaned | **Confirmed** | Fixture on disk, not in manifest |
| detect_changes vacuous | **Confirmed** | All `expect: {}`, golden stores count only |
| Nightly failures invisible | **Confirmed** | `continue-on-error: true` on both steps |
| Assertion looseness | **Mixed** | Loose by design, golden compensates; but some should be tighter |
| search_graph translation mask | **Overstated** | API difference requires translation; assertion-level check is appropriate |
| Missing language coverage | **Confirmed** | No Go fixture despite Go extractor support |

---

## 5. Remediation Strategy

### Phase A: Close assertion gaps (S effort)

No new fixtures needed. Tighten existing coverage.

1. **I1**: Add `get_code_snippet`, `get_graph_schema`, `index_status`, `delete_project` assertions to `python-parity` fixture in manifest.
2. **I3**: Replace `{"expect": {}}` with `{"expect": {"changed_count": 0}}` (or actual expected count) for all `detect_changes` assertions.
3. **I7**: Add `required_rows_min: 1` to all `query_graph` assertions expected to return rows (use golden snapshot data as reference).
4. **I13**: `chmod +x scripts/run_cli_parity.sh`.
5. **I5**: Update `SHARED_PROGRESS_PHASES` to include [5/9], [7/9], [8/9].

### Phase B: Wire in orphaned fixture + new fixtures (M effort)

6. **I2**: Add `scip` fixture to `manifest.json` with index + search_graph + query_graph assertions.
7. **I6**: Create `go-basic` and `go-parity` fixtures.
8. **I11**: Create `zig-parity` fixture with richer Zig patterns.
9. **I10**: Create `error-paths` fixture exercising error responses.

### Phase C: CI and reporting (S effort)

10. **I4**: Remove `continue-on-error: true` from nightly workflow, or add a summary/notification step.
11. **I9**: Add diff detail to golden comparison for `search_code`, `trace_call_path`, `get_architecture`.
12. **I12**: Store actual index counts in golden snapshot alongside thresholds.

---

## 6. Ranked Backlog Checklist

| # | Issue | Size | Phase | Depends On |
|---|-------|------|-------|------------|
| 1 | I1: Add assertions for 4 uncovered tools | S | A | -- |
| 2 | I4: Fix nightly CI continue-on-error | S | C | -- |
| 3 | I3: Add detect_changes expected values | S | A | -- |
| 4 | I7: Add required_rows_min to query assertions | S | A | -- |
| 5 | I2: Wire SCIP fixture into manifest | S | B | -- |
| 6 | I10: Add error-path fixture | M | B | -- |
| 7 | I6: Add Go fixtures | M | B | -- |
| 8 | I9: Add diff detail to golden comparison | S | C | -- |
| 9 | I12: Store actual index counts in golden | S | C | -- |
| 10 | I5: Update SHARED_PROGRESS_PHASES | S | A | -- |
| 11 | I11: Add zig-parity fixture | S | B | -- |
| 12 | I13: Fix cli_parity.sh permissions | S | A | -- |
| 13 | I8: Document search_graph translation | S | A | -- |

---

## 7. Final Judgment

### What the interop infrastructure gets right

**The three-mode design is well-architected.** `compare` (full C vs Zig), `zig-only` (golden snapshot regression), and `update-golden` (intentional baseline update) cover the lifecycle cleanly. The golden snapshot mechanism allows CI gating without requiring the C binary.

**Canonicalization is thorough.** The harness normalizes paths, sorts results, strips implementation-specific fields, and handles divergent response shapes (C wraps vs Zig direct). The `canonical_*` functions are well-tested by the fact that 11 fixtures pass consistently.

**The manifest-driven design is extensible.** Adding a new fixture requires only a directory of source files and a manifest entry. The harness automatically generates the full MCP request sequence from the manifest.

**Fixture coverage across languages is solid for what exists.** Python, JavaScript, TypeScript, and Rust each have basic + parity fixtures covering classes, functions, inheritance, interfaces, decorators, config files, and multiple edge types.

### The most important real gaps

1. **4 MCP tools (31%) have zero behavioral coverage** (I1). `get_code_snippet` is a primary user-facing tool and could regress undetected.
2. **Nightly full-comparison is not a gate** (I4). The weekly Zig-vs-C comparison always succeeds, making it an artifact nobody looks at.
3. **`detect_changes` is exercised but never validated** (I3). The tool is called, the response is ignored.

### What should be treated as debt

- **Search_graph parameter translation** (I8): inherent API difference, acceptable.
- **Index count thresholds vs actuals** (I12): minor, golden strictness compensates elsewhere.
- **Zig-parity fixture** (I11): nice-to-have, zig-basic covers the critical path.

### Minimum high-leverage next actions

1. **Add 4 tool assertions to python-parity** (~30 min). Closes I1.
2. **Remove `continue-on-error: true` from nightly** (~5 min). Closes I4.
3. **Wire SCIP fixture into manifest** (~30 min). Closes I2.
4. **Add `required_rows_min` and `detect_changes` expectations** (~1 hr). Closes I3 + I7.

These four actions raise behavioral coverage from 69% to 100% of MCP tools, make the nightly comparison a real gate, and eliminate the two largest assertion blindspots.
