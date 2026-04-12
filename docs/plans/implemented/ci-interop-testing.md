# A15: CI Interop Testing Gaps

**Origin:** Architecture review issue A15 + interop testing review (2026-04-12)
**Status:** New
**Size:** L (7 phases, individually S-M)
**Source:** `docs/interop-testing-review.md`

## Problem

The interop harness infrastructure is well-architected (three-mode design, canonical normalization, manifest-driven fixtures) but has meaningful coverage gaps:

- 4 of 13 MCP tools (31%) have zero behavioral assertions
- Nightly Zig-vs-C comparison failures are invisible (`continue-on-error: true`)
- `detect_changes` is invoked but never validated
- 20 `query_graph` assertions accept empty results where rows are expected
- SCIP fixture exists on disk but is orphaned from the manifest
- No Go fixtures despite Go extractor support
- No error-path test cases

## File Map

### Modify
- `testdata/interop/manifest.json` (phases 2-5: assertion tightening, new tool coverage, new fixtures)
- `scripts/run_interop_alignment.sh` (phases 1, 3, 6: progress phases, tool harness support, golden diff detail)
- `.github/workflows/interop-nightly.yml` (phase 1: remove continue-on-error)
- `scripts/run_cli_parity.sh` (phase 1: chmod +x)
- `testdata/interop/golden/*.json` (phases 2-5: regenerate after manifest changes)

### Create
- `testdata/interop/go-basic/main.go` (phase 5)
- `testdata/interop/go-parity/main.go` (phase 5)
- `testdata/interop/go-parity/go.mod` (phase 5)
- `testdata/interop/zig-parity/main.zig` (phase 5)

---

## Phase 1: Quick wins [S] — status: pending

No functional risk. Independent changes.

### 1a. Remove continue-on-error from nightly CI (I4)

In `.github/workflows/interop-nightly.yml`, remove `continue-on-error: true` from lines 51 and 57 (the "Run full interop comparison" and "Run full CLI parity comparison" steps).

- [ ] Remove `continue-on-error: true` from interop comparison step (line 51)
- [ ] Remove `continue-on-error: true` from CLI parity step (line 57)

### 1b. Fix cli_parity.sh permissions (I13)

- [ ] `chmod +x scripts/run_cli_parity.sh`

### 1c. Update SHARED_PROGRESS_PHASES (I5)

In `scripts/run_interop_alignment.sh`, update the `SHARED_PROGRESS_PHASES` tuple (line 92-102) and the `canonical_progress_lines` function (line 551-565).

Current phases checked: [1/9], [2/9], [3/9], [4/9], [9/9]
Missing phases emitted by Zig (`src/main.zig:364-366`): [5/9] "Detecting tests", [7/9] "Analyzing git history", [8/9] "Linking config files". No [6/9] exists.

- [ ] Add `"[5/9] Detecting tests"`, `"[7/9] Analyzing git history"`, `"[8/9] Linking config files"` to `SHARED_PROGRESS_PHASES`
- [ ] Update `canonical_progress_lines` to also match `[5/9]`, `[7/9]`, `[8/9]` prefixes
- [ ] Add comment documenting that [6/9] is intentionally absent

### 1d. Document search_graph parameter translation (I8)

- [ ] Add a comment in `build_requests` (line 641) explaining that `label` is translated to `label_pattern` for Zig because the APIs differ, and that this means comparison is assertion-level, not output-level, for `search_graph`

---

## Phase 2: Tighten existing assertions [S] — status: pending

Manifest-only changes. No harness code changes needed.

### 2a. Fix detect_changes assertions (I3)

All three parity fixtures with `detect_changes` use `{"expect": {}}`. These fixtures have no uncommitted changes (they're static test directories), so `changed_count` should be 0 in assertion mode. The golden snapshot confirms `detect_changes_count: 1` (meaning 1 call was made, not 1 change).

Replace in `testdata/interop/manifest.json`:

**python-parity** (manifest line ~791):
```json
"detect_changes": [{ "args": { "scope": "impact" }, "expect": {} }]
```
becomes:
```json
"detect_changes": [{ "args": { "scope": "impact" }, "expect": { "changed_count": 0 } }]
```

Same change for **javascript-parity** (line ~1012) and **typescript-parity** (line ~1264) and **rust-parity** (line ~1571).

- [ ] python-parity: add `"changed_count": 0` to detect_changes expect
- [ ] javascript-parity: add `"changed_count": 0` to detect_changes expect
- [ ] typescript-parity: add `"changed_count": 0` to detect_changes expect
- [ ] rust-parity: add `"changed_count": 0` to detect_changes expect

### 2b. Add required_rows_min to query_graph assertions (I7)

Add `"required_rows_min": 1` to every `query_graph` assertion where the golden snapshot has non-empty rows but the manifest has no minimum. Leave assertions that genuinely return 0 rows untouched.

**python-parity** (7 assertions to fix, 0-indexed within query_graph array):
- [5] DECORATES query — golden has 1 row → add `required_rows_min: 1`
- [7] Variable names — golden has 4 rows → add `required_rows_min: 1`
- [8] CONFIGURES — golden has 1 row → add `required_rows_min: 1`
- [11] IMPORTS — golden has 1 row → add `required_rows_min: 1`
- [12] DEFINES main.py Module — golden has 1 row → add `required_rows_min: 1`
- [13] DEFINES models.py Method — golden has 3 rows → add `required_rows_min: 1`
- [14] DEFINES settings.yaml Variable — golden has 3 rows → add `required_rows_min: 1`

Leave untouched (genuinely empty): [5] INHERITS, [9] WRITES, [10] USES_TYPE

**javascript-parity** (3 assertions to fix):
- [5] Variable names — golden has 2 rows → add `required_rows_min: 1`
- [6] File names — golden has 1 row → add `required_rows_min: 1`
- [7] Module names — golden has 1 row → add `required_rows_min: 1`

Leave untouched: [4] WRITES (empty)

**typescript-parity** (3 assertions to fix):
- [7] File names — golden has 1 row → add `required_rows_min: 1`
- [8] Module names — golden has 1 row → add `required_rows_min: 1`
- [9] Method names — golden has 1 row → add `required_rows_min: 1`

Leave untouched: [3] IMPLEMENTS, [4] WRITES, [5] USES_TYPE, [6] Variable names (all empty)

**rust-parity** (7 assertions to fix):
- [6] Class names — golden has 3 rows → add `required_rows_min: 1`
- [7] Field names — golden has 2 rows → add `required_rows_min: 1`
- [9] Variable names — golden has 3 rows → add `required_rows_min: 1`
- [10] DEFINES_METHOD — golden has 2 rows → add `required_rows_min: 1`
- [11] DEFINES lib.rs Module — golden has 1 row → add `required_rows_min: 1`
- [12] DEFINES lib.rs Field — golden has 2 rows → add `required_rows_min: 1`
- [13] DEFINES Cargo.toml Variable — golden has 3 rows → add `required_rows_min: 1`

Leave untouched: [5] USES_TYPE (empty)

- [ ] python-parity: add required_rows_min to 7 query_graph assertions
- [ ] javascript-parity: add required_rows_min to 3 query_graph assertions
- [ ] typescript-parity: add required_rows_min to 3 query_graph assertions
- [ ] rust-parity: add required_rows_min to 7 query_graph assertions

### 2c. Regenerate golden snapshots

After manifest changes, golden snapshots must be regenerated since detect_changes assertion behavior doesn't affect golden content, but we should verify nothing breaks.

- [ ] Run `bash scripts/run_interop_alignment.sh --zig-only` and confirm all 11 fixtures pass
- [ ] If any fail, investigate before proceeding

---

## Phase 3: Add 4 uncovered tools to harness + manifest [M] — status: pending

This is the highest-impact phase. Requires both harness code changes and manifest entries. The 4 uncovered tools are: `get_code_snippet`, `get_graph_schema`, `index_status`, `delete_project`.

### 3a. Harness changes in `scripts/run_interop_alignment.sh`

For each tool, add:
1. A `canonical_*` normalization function
2. A loop in `build_requests` to emit tool calls from manifest assertions
3. A handler in `check_assertions` to validate responses
4. Entries in `build_golden_snapshot` and `compare_golden_snapshot`

**get_graph_schema**: Returns `{node_labels: [...], edge_types: [...]}`. Canonical form: sorted unique label/type strings. Reuse `canonical_architecture` or create a thin wrapper.

**get_code_snippet**: Returns `{source: "...", qualified_name: "...", ...}`. Canonical form: strip absolute path prefixes, keep source and qualified_name. Assert on `source_contains` and `qualified_name_contains`.

**index_status**: Returns `{status: "...", project: "..."}`. Canonical form: check status field is "indexed" after index_repository. Trivial assertion.

**delete_project**: Stateful. Must be called LAST in the request sequence (after `list_projects`). Assert return status, then optionally verify `list_projects` no longer contains the project. Add as the final request in `build_requests`.

- [ ] Add `canonical_graph_schema` function (sort labels and edge types)
- [ ] Add `canonical_code_snippet` function (normalize paths in response)
- [ ] Add `build_requests` loop for `get_graph_schema` assertions
- [ ] Add `build_requests` loop for `get_code_snippet` assertions
- [ ] Add `build_requests` loop for `index_status` assertions (after index_repository)
- [ ] Add `build_requests` entry for `delete_project` (after list_projects, at end of sequence)
- [ ] Add `check_assertions` handlers for all 4 tools
- [ ] Add `build_golden_snapshot` entries for all 4 tools
- [ ] Add `compare_golden_snapshot` entries with diff detail for all 4 tools
- [ ] Add compare-mode comparison blocks for all 4 tools in `run_compare_mode`

### 3b. Manifest assertions in python-parity

Add assertions to the `python-parity` fixture (most comprehensive, best candidate):

**get_graph_schema** (after index_repository):
```json
"get_graph_schema": [{
  "args": {},
  "expect": {
    "required_node_labels": ["Class", "File", "Function", "Module"],
    "required_edge_types": ["CALLS", "DEFINES", "IMPORTS"]
  }
}]
```

**get_code_snippet** (requires a known qualified_name — use "bootstrap" from python-parity):
```json
"get_code_snippet": [{
  "args": {
    "qualified_name": "python-parity:main.py:python:symbol:python:bootstrap"
  },
  "expect": {
    "source_contains": ["def bootstrap"],
    "has_source": true
  }
}]
```

**index_status** (after index_repository):
```json
"index_status": [{
  "args": {},
  "expect": {
    "status": "indexed"
  }
}]
```

**delete_project** (at end of sequence):
```json
"delete_project": [{
  "args": {},
  "expect": {
    "status": "deleted"
  }
}]
```

- [ ] Add `get_graph_schema` assertion to python-parity in manifest
- [ ] Add `get_code_snippet` assertion to python-parity in manifest
- [ ] Add `index_status` assertion to python-parity in manifest
- [ ] Add `delete_project` assertion to python-parity in manifest
- [ ] Add `get_graph_schema`, `get_code_snippet`, `index_status`, `delete_project` to python-parity `scope_tools`

### 3c. Verify and regenerate golden snapshots

- [ ] Run `bash scripts/run_interop_alignment.sh --update-golden`
- [ ] Run `bash scripts/run_interop_alignment.sh --zig-only` and confirm all fixtures pass
- [ ] Verify the new python-parity golden snapshot contains entries for the 4 new tools

---

## Phase 4: Wire SCIP fixture [S] — status: pending

The fixture directory `testdata/interop/scip/` already exists with `src/main.ts` and `.codebase-memory/scip.json` (defines `renderMessage` and `run` symbols via SCIP overlay).

### 4a. Add SCIP fixture to manifest

```json
{
  "id": "scip",
  "path": "testdata/interop/scip",
  "project": "scip",
  "language": "typescript",
  "scope_tools": ["index_repository", "search_graph", "query_graph", "list_projects"],
  "assertions": {
    "index_repository": {
      "expect": { "nodes_min": 3, "edges_min": 1 }
    },
    "search_graph": [{
      "args": { "project": "scip", "label": "Function" },
      "expect": { "required_names": ["renderMessage", "run"] }
    }],
    "query_graph": [{
      "args": {
        "query": "MATCH (n) WHERE n.label = \"Function\" RETURN n.name ORDER BY n.name ASC",
        "project": "scip",
        "max_rows": 20
      },
      "expect": {
        "columns": ["n.name"],
        "required_rows_min": 1
      }
    }]
  }
}
```

- [ ] Add scip fixture entry to manifest.json
- [ ] Run `bash scripts/run_interop_alignment.sh --update-golden` to generate `testdata/interop/golden/scip.json`
- [ ] Run `bash scripts/run_interop_alignment.sh --zig-only` and confirm scip passes

---

## Phase 5: New language fixtures [M] — status: pending

### 5a. Create Go fixtures

**go-basic** — minimal Go file exercising package-level functions:

`testdata/interop/go-basic/main.go`:
```go
package main

import "fmt"

func greet(name string) string {
    return fmt.Sprintf("hello %s", name)
}

func run() {
    fmt.Println(greet("world"))
}
```

**go-parity** — richer Go patterns: interfaces, structs, methods, multiple return values:

`testdata/interop/go-parity/main.go`:
```go
package main

import "fmt"

type Runner interface {
    Run() string
}

type Config struct {
    Mode    string
    Verbose bool
}

type Worker struct {
    Config Config
}

func (w *Worker) Run() string {
    return fmt.Sprintf("running in %s mode", w.Config.Mode)
}

func NewWorker(mode string) *Worker {
    return &Worker{Config: Config{Mode: mode, Verbose: false}}
}

func boot() string {
    w := NewWorker("batch")
    return w.Run()
}
```

`testdata/interop/go-parity/go.mod`:
```
module go-parity

go 1.21
```

Manifest assertions for each: `index_repository`, `search_graph` (Function, Class/struct, Interface), `query_graph` (CALLS, DEFINES_METHOD), `trace_call_path`, `list_projects`.

- [ ] Create `testdata/interop/go-basic/main.go`
- [ ] Create `testdata/interop/go-parity/main.go` and `go.mod`
- [ ] Add `go-basic` fixture to manifest with assertions
- [ ] Add `go-parity` fixture to manifest with assertions
- [ ] Generate golden snapshots for both Go fixtures
- [ ] Verify `--zig-only` passes for both

### 5b. Create zig-parity fixture

`testdata/interop/zig-parity/main.zig` — richer Zig patterns: error unions, tagged unions, test blocks, structs with methods:

```zig
const std = @import("std");

pub const Status = enum { idle, running, done };

pub const Config = struct {
    mode: []const u8,
    retries: u8 = 3,

    pub fn isVerbose(self: Config) bool {
        return std.mem.eql(u8, self.mode, "verbose");
    }
};

pub fn createConfig(mode: []const u8) Config {
    return Config{ .mode = mode };
}

pub fn boot() !void {
    const cfg = createConfig("batch");
    if (cfg.isVerbose()) {
        std.debug.print("verbose mode\n", .{});
    }
}

test "config defaults" {
    const cfg = Config{ .mode = "test" };
    try std.testing.expectEqual(@as(u8, 3), cfg.retries);
}
```

- [ ] Create `testdata/interop/zig-parity/main.zig`
- [ ] Add `zig-parity` fixture to manifest with assertions (search_graph for Function/Class, query_graph for DEFINES_METHOD, trace_call_path)
- [ ] Generate golden snapshot
- [ ] Verify `--zig-only` passes

---

## Phase 6: Golden comparison improvements [S] — status: pending

### 6a. Add diff detail to golden comparison (I9)

In `compare_golden_snapshot` (line 1009-1145 of `scripts/run_interop_alignment.sh`), `search_code`, `trace_call_path`, `get_architecture`, and `manage_adr` just say "differs" on mismatch. Add the same added/removed detail already used for `query_graph`.

**search_code**: Compare `results` lists, show added/removed entries by `(name, file_path, label)` tuple.
**trace_call_path**: Compare edge lists, show added/removed `(source, target, type)` tuples.
**get_architecture**: Compare `node_labels` and `edge_types` lists, show added/removed.

- [ ] Add diff detail to `search_code` comparison in `compare_golden_snapshot`
- [ ] Add diff detail to `trace_call_path` comparison
- [ ] Add diff detail to `get_architecture` comparison
- [ ] Add diff detail to `manage_adr` comparison

### 6b. Store actual index counts in golden (I12)

In `build_golden_snapshot` (line 999-1004), store actual `nodes` and `edges` counts from the Zig output alongside the manifest thresholds. In `compare_golden_snapshot`, alert if actual counts drop by more than 20% from the golden values.

- [ ] Modify `build_golden_snapshot` to store `nodes_actual` and `edges_actual`
- [ ] Modify `compare_golden_snapshot` to check actual counts against golden with 20% tolerance
- [ ] Regenerate golden snapshots to include actual counts

---

## Phase 7: Error-path fixture [M] — status: pending

### 7a. Harness support for error assertions

The current harness only tests happy paths. Error-path testing requires:

1. A way to mark assertions as expecting an error response (e.g., `"expect_error": true`)
2. The `check_assertions` function to validate error shape instead of success shape
3. A fixture that sends requests expected to fail

Add an `"expect_error"` field to the assertion schema. When present, `check_assertions` verifies the response contains `"error"` in the JSON-RPC envelope rather than `"result"`.

- [ ] Add `expect_error` handling to `extract_tool_payload` and `check_assertions`
- [ ] Add error response to `build_golden_snapshot` and `compare_golden_snapshot`

### 7b. Create error-paths fixture

A minimal fixture with a single source file, plus assertions that exercise error responses:

- `query_graph` with invalid Cypher syntax
- `get_code_snippet` with a non-existent `qualified_name`
- `search_graph` on a non-existent project (before indexing a different name)

- [ ] Create `testdata/interop/error-paths/main.py` (minimal file)
- [ ] Add `error-paths` fixture to manifest with error assertions
- [ ] Generate golden snapshot
- [ ] Verify `--zig-only` passes

---

## Verification gate

After all phases:

- [ ] `bash scripts/run_interop_alignment.sh --zig-only` — all fixtures pass (including new ones)
- [ ] `bash scripts/run_cli_parity.sh --zig-only` — passes
- [ ] `zig build test` — unit tests still pass
- [ ] Push to branch and verify CI passes (ci.yml)
