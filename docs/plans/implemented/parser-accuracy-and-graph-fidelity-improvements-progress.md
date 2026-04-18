# Parser Accuracy and Graph Fidelity Progress

## Scope

This plan closes accuracy bugs that make the graph wrong on the Zig port's
already-supported languages before expanding the broader product surface.

Current focus:
- owner retention for definitions, calls, imports, and usages
- false route detection on current framework rules
- import-aware resolution on the parser-backed JS/TS/Python surface

Deferred but still tracked in this plan:
- unsupported-language parity lanes for C++, R, and embedded Svelte/Vue script
  extraction
- broader indirect-call and semantic-graph expansion, which belong in the later
  semantic expansion cluster

## Phase 1 Contract

### Bucketed issue map

| Bucket | Upstream issue families | Contract in this plan |
|--------|--------------------------|-----------------------|
| Current target-language correctness | `#5`, `#6`, `#7`, `#8`, `#26`, `#43`, `#180`, `#236` | Add fixtures and later implementation work for false route detection, import-aware resolution, and owner retention on already-supported Python/JS/TS behavior. |
| Deferred unsupported-language parity | `#9`, `#218`, `#219`, `#223` | Capture exact fixture shapes now, but do not claim current-contract parity until those languages or embedded-script surfaces are truly supported. |
| Future semantic-graph expansion | `#27`, `#28`, `#29`, `#55`, `#56`, `#220`, `#228` | Document as follow-on semantic work rather than silently broadening this correctness-only plan. |

### Fixture inventory

- `testdata/interop/accuracy/python-framework-cases/main.py`
  - Route-decorator false-positive guard
  - Module-vs-function ownership around decorator-backed handlers
- `testdata/interop/accuracy/typescript-import-cases/index.ts`
  - Alias-aware import resolution and call ownership
  - Namespace and named import shapes in the current TypeScript surface
- `testdata/interop/accuracy/cpp-resolution-cases/main.cpp`
  - Deferred unsupported-language lane for namespace and method ownership
- `testdata/interop/accuracy/r-box-cases/main.R`
  - Deferred unsupported-language lane for `box::use()` and assignment-based
    function ownership
- `testdata/interop/accuracy/svelte-vue-import-cases/App.svelte`
  - Deferred embedded-script lane for import extraction inside `<script>`

### Expected verification queries

Planned assertion shapes for the future manifest or direct MCP checks:

- `search_graph`
  - Python fixture: `Function` rows must include `create_app`, `health_check`,
    `build_router`, and `not_a_route`
  - TypeScript fixture: `Function` rows must include `run`, `handleRequest`, and
    `parsePayload`
- `query_graph`
  - Python fixture:
    `MATCH (a)-[r:HANDLES]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC`
    should only expose the decorated handler relationship, not helper callsites
    or dict literals that look route-like.
  - TypeScript fixture:
    `MATCH (a)-[r:CALLS]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC`
    should preserve alias-aware resolution rather than collapsing to module-only
    ownership.
  - Embedded-script and unsupported-language fixtures:
    definition inventory queries should stay diagnostic until those lanes are
    promoted out of deferred.
- `trace_call_path`
  - TypeScript fixture: tracing from `run` outbound should hit
    `handleRequest` and `parsePayload` through the resolved call path instead of
    stopping at an unresolved alias or module node.

### Exact verification commands

Phase 1 records the commands that Phase 3 will run after implementation:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_interop_alignment.sh
```

Fixture-specific direct checks to add once the manifest rows land:

```sh
zig build run -- cli index_repository '{"project_path":"testdata/interop/accuracy/python-framework-cases","mode":"full"}'
zig build run -- cli search_graph '{"project":"python-framework-cases","label_pattern":"Function"}'
zig build run -- cli query_graph '{"project":"python-framework-cases","query":"MATCH (a)-[r:HANDLES]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'
zig build run -- cli index_repository '{"project_path":"testdata/interop/accuracy/typescript-import-cases","mode":"full"}'
zig build run -- cli trace_call_path '{"project":"typescript-import-cases","function_name":"run","direction":"out","depth":4}'
```

## Initial Baseline Probe

Controlled probe run on 2026-04-18 after bootstrapping the worktree:

- Python fixture:
  - `index_repository` returned `nodes=10`, `edges=12`
  - `search_graph(label_pattern="Function")` returned `build_router`,
    `create_app`, `health_check`, `not_a_route`, and `read_status`
  - `HANDLES` query returned no rows on the current baseline, which means the
    decorator-backed route edge is still a red case instead of a green one
- TypeScript fixture:
  - `index_repository` returned `nodes=12`, `edges=16`
  - `search_graph` returned `run`, `localOnly`, `markStart`, `parsePayload`,
    and `handleRequest`
  - `trace_call_path(function_name=\"run\")` resolved outbound `CALLS` edges to
    `markStart`, `parsePayload`, and `handleRequest`

What this means:
- the first TypeScript alias-resolution guard is green already
- the Python fixture is useful, but still exposes missing framework-backed route
  attachment rather than proving it solved
- Phase 2 should target the Python route-attachment red case plus any ownership
  drift that appears when fixture-backed assertions are added

## Phases

### Phase 1: Lock the Accuracy Contract
- [x] Bucketed the upstream issue families into current-contract correctness,
  deferred unsupported-language parity, and future semantic-graph expansion.
- [x] Added fixture skeletons under `testdata/interop/accuracy/` for each lane.
- [x] Recorded the expected verification queries and exact command shapes for
  the future parity checks.
- **Status:** complete

### Phase 2: Repair Ownership and Resolution Rules
- [x] Update extraction ownership and route false-positive handling on the
  current parser-backed languages.
- [x] Preserve import alias and ambiguity information through registry, store,
  and query surfaces.
- [x] Add only the minimum explicit framework rules required for the verified
  current-language fixtures.
- **Status:** complete

## Phase 2 Recheck

Revalidated on 2026-04-18 from refreshed `main` in a rebuilt worktree:

- Python fixture:
  - direct CLI indexing returned `nodes=10`, `edges=12`
  - direct `HANDLES` query returned exactly `health_check -> /health`
  - the earlier "no rows" baseline in this progress file was stale relative to
    the current branch tip
- TypeScript fixture:
  - direct CLI indexing returned `nodes=12`, `edges=16`
  - direct `trace_call_path(function_name=\"run\")` returned outbound `CALLS`
    edges to `markStart`, `parsePayload`, and `handleRequest`

What this means:

- the current Python false-route / decorator-backed handler case is green on the
  refreshed branch
- the current TypeScript alias-aware call-resolution case is green on the Zig
  CLI surface
- unsupported-language lanes remain deferred on purpose; no attempt was made to
  promote the C++, R, or embedded Svelte/Vue fixtures into the current shipped
  contract

### Phase 3: Verify and Reclassify
- [x] Add fixture-specific interop assertions to `testdata/interop/manifest.json`
  and re-run the harness plus direct MCP checks.
- [x] Reclassify only the rows in `docs/port-comparison.md` that now have
  fixture-backed evidence.
- [x] Leave unsupported-language and semantic-expansion lanes deferred unless
  the verification evidence changes.
- **Status:** complete

## Phase 3 Completion Pass

Verification completed on 2026-04-18:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
env CODEBASE_MEMORY_ZIG_BIN="$PWD/zig-out/bin/cbm" bash scripts/run_interop_alignment.sh
```

Direct MCP probes run in isolated temp-home environments:

```sh
./zig-out/bin/cbm cli index_repository '{"project_path":"testdata/interop/accuracy/python-framework-cases","mode":"full"}'
./zig-out/bin/cbm cli query_graph '{"project":"python-framework-cases","query":"MATCH (a)-[r:HANDLES]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'
./zig-out/bin/cbm cli index_repository '{"project_path":"testdata/interop/accuracy/typescript-import-cases","mode":"full"}'
./zig-out/bin/cbm cli trace_call_path '{"project":"typescript-import-cases","function_name":"run","direction":"out","depth":4}'
```

Results:

- `zig build` passed
- `zig build test` passed
- `bash scripts/run_interop_alignment.sh` passed and rewrote:
  - `.interop_reports/interop_alignment_report.json`
  - `.interop_reports/interop_alignment_report.md`
- New parser-accuracy fixture status from the harness:
  - `python-framework-cases`
    - no Zig assertion failures
    - no C assertion failures
    - shared `search_graph` and `query_graph` comparisons matched
  - `typescript-import-cases`
    - no Zig assertion failures
    - no C assertion failures
    - shared `search_graph` and `trace_call_path` comparisons matched
- Direct Zig-only CLI checks showed:
  - Python `HANDLES` rows: `health_check -> /health`
  - TypeScript `trace_call_path(run)` callees:
    `markStart`, `parsePayload`, `handleRequest`

## Remaining Risks and Deferred Lanes

This plan intentionally leaves these lanes deferred:

- `cpp-resolution-cases`
  - unsupported-language ownership and namespace-resolution lane
- `r-box-cases`
  - unsupported-language `box::use()` and assignment-ownership lane
- `svelte-vue-import-cases`
  - embedded-script extraction lane outside the current parser-backed contract

Unrelated pre-existing mismatches still present in the full shared harness:

- `python-parity` `get_code_snippet`
- `javascript-parity` `query_graph`
- `go-basic` `search_graph`
- `go-parity` `search_graph`
- `go-parity` `query_graph`
- `zig-parity` `search_graph`
- `error-paths` `get_code_snippet`

Those mismatches were not introduced by this plan and are outside the narrower
current-language accuracy tranche validated here.
