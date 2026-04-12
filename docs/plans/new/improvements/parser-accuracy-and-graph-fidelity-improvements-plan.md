# Plan: Parser Accuracy and Graph Fidelity Improvements

## Goal
Close the upstream accuracy bugs that make the graph wrong rather than merely incomplete, with fixture-backed contracts for node extraction, edge attribution, route disambiguation, and import-aware resolution.

## Research Basis

Upstream issue families captured in this plan:
- Mis-extracted or unnamed definitions: `#5`, `#6`, `#9`, `#236`
- False route or false dead-code signals: `#7`, `#8`, `#27`, `#28`
- Ambiguous cross-module or cross-file resolution: `#26`, `#43`, `#180`, `#220`, `#228`
- Missing import or call semantics in embedded or language-specific syntax: `#218`, `#219`, `#223`
- Adjacent semantic pressure that depends on the same substrate: `#29`, `#55`, `#56`

Upstream PRs that show the likely implementation shape:
- Resolver and entry-point fixes: `#23`, `#25`
- Route and parser false-positive fixes: `#65`, `#66`
- Call extraction repair: `#47`
- Search and trace parameter wiring: `#155`
- ES/TS import-resolution follow-on: `#184`
- Decorator-call enrichment: `#208`
- Embedded-script import extraction: `#224`

Observed upstream pattern:
- Accuracy regressions repeatedly came from fallback behavior that silently attached edges to modules, guessed routes from broad syntax, or ignored import/package context.
- The upstream project improved reliability when it added small, explicit language- or framework-specific rules plus regression fixtures instead of trying to generalize everything through one heuristic.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-plan.md`
- Create: `docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/registry.zig`
- Modify: `src/store.zig`
- Modify: `src/cypher.zig`
- Modify: `src/mcp.zig`
- Create: `testdata/interop/accuracy/python-framework-cases/main.py`
- Create: `testdata/interop/accuracy/typescript-import-cases/index.ts`
- Create: `testdata/interop/accuracy/cpp-resolution-cases/main.cpp`
- Create: `testdata/interop/accuracy/r-box-cases/main.R`
- Create: `testdata/interop/accuracy/svelte-vue-import-cases/App.svelte`

## Phases

### Phase 1: Lock the Accuracy Contract
- [ ] Map each upstream bug in this tranche to one of three buckets in `docs/gap-analysis.md`: current target-language correctness, deferred unsupported-language parity, or future semantic-graph expansion.
- [ ] Add focused fixtures under `testdata/interop/accuracy/` for the exact upstream failure modes that overlap the Zig architecture: false route detection, import-aware resolution, module-vs-function ownership, and embedded-script import extraction.
- [ ] Record the expected graph queries, expected labels, and exact verification commands in `docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-progress.md`.
- **Status:** pending

### Phase 2: Repair Ownership and Resolution Rules
- [ ] Extend `src/extractor.zig` and `src/pipeline.zig` so parser-backed extraction retains the enclosing owner for definitions, calls, imports, route handlers, and framework entry points instead of falling back to file-level ownership when context is available.
- [ ] Strengthen `src/registry.zig`, `src/store.zig`, `src/cypher.zig`, and `src/mcp.zig` so package-aware, alias-aware, and ambiguity-aware lookup is preserved through storage and query surfaces rather than being collapsed into name-only matches.
- [ ] Add the minimum explicit framework rules needed for current target languages first, and defer unsupported-language fixes as tracked fixture gaps instead of silently claiming parity.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh`, then add fixture-specific `search_graph`, `query_graph`, and `trace_call_path` checks for each accuracy case until output is stable.
- [ ] Update `docs/port-comparison.md` so graph-fidelity rows move only where a fixture-backed parity claim now exists.
- [ ] Record still-deferred unsupported-language cases and follow-on semantic work in `docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Prioritize correctness on already-supported languages before onboarding new grammars | The upstream backlog shows that false positives and wrong ownership erode trust faster than missing long-tail language support. |
| Treat unsupported-language reports as fixture-backed deferred lanes, not silent omissions | That preserves research value from the upstream issues without overstating current-port coverage. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
