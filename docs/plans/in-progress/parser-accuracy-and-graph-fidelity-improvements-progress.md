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
zig build run -- cli search_graph '{"project":"python-framework-cases","label":"Function"}'
zig build run -- cli query_graph '{"project":"python-framework-cases","query":"MATCH (a)-[r:HANDLES]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'
zig build run -- cli index_repository '{"project_path":"testdata/interop/accuracy/typescript-import-cases","mode":"full"}'
zig build run -- cli trace_call_path '{"project":"typescript-import-cases","function_name":"run","direction":"out","depth":4}'
```

## Initial Baseline Probe

Controlled probe run on 2026-04-18 after bootstrapping the worktree:

- Python fixture:
  - `index_repository` returned `nodes=10`, `edges=12`
  - `HANDLES` query returned only `health_check -> /health`
- TypeScript fixture:
  - `index_repository` returned `nodes=12`, `edges=16`
  - `search_graph` returned `run`, `localOnly`, `markStart`, `parsePayload`,
    and `handleRequest`
  - `trace_call_path(function_name=\"run\")` resolved outbound `CALLS` edges to
    `markStart`, `parsePayload`, and `handleRequest`

What this means:
- the first Python false-route guard and the first TypeScript alias-resolution
  guard are green already
- Phase 2 should now target a sharper red case around ownership drift or
  framework-specific attachment instead of changing extraction blindly

## Phases

### Phase 1: Lock the Accuracy Contract
- [x] Bucketed the upstream issue families into current-contract correctness,
  deferred unsupported-language parity, and future semantic-graph expansion.
- [x] Added fixture skeletons under `testdata/interop/accuracy/` for each lane.
- [x] Recorded the expected verification queries and exact command shapes for
  the future parity checks.
- **Status:** complete

### Phase 2: Repair Ownership and Resolution Rules
- [ ] Update extraction ownership and route false-positive handling on the
  current parser-backed languages.
- [ ] Preserve import alias and ambiguity information through registry, store,
  and query surfaces.
- [ ] Add only the minimum explicit framework rules required for the verified
  current-language fixtures.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Add fixture-specific interop assertions to `testdata/interop/manifest.json`
  and re-run the harness plus direct MCP checks.
- [ ] Reclassify only the rows in `docs/port-comparison.md` that now have
  fixture-backed evidence.
- [ ] Leave unsupported-language and semantic-expansion lanes deferred unless
  the verification evidence changes.
- **Status:** pending
