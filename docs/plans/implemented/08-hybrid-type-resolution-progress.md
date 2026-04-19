# Hybrid Type Resolution Progress

## Scope

Completed first slice:
- accept an optional repository sidecar at
  `.codebase-memory/hybrid-resolution.json`
- use that sidecar to resolve explicit Go call targets before the existing
  registry heuristic path runs
- keep the no-sidecar path stable and verified

Intentional non-goals for this completed slice:
- live `gopls`, `clangd`, or other external process integration
- C/C++ hybrid resolution claims before the Zig port has parser-backed C/C++
  extraction coverage
- compile-commands ingestion or broader type-evaluation machinery

## Contract

Source review on 2026-04-19 showed the original hybrid path is best understood
as an internal registry-plus-sidecar resolver, not just "spawn an LSP server and
hope." The bounded Zig overlap is therefore:

- repository-owned explicit resolved-call data
- parser-backed call sites that already exist in the Zig extractor
- preference for explicit sidecar targets over low-confidence heuristic
  registry matches
- silent functional fallback to the current registry path when the sidecar is
  absent

For this branch, the verified surface is Go only.

## Implementation Notes

Implemented on 2026-04-19:

- added `src/hybrid_resolution.zig` to parse the optional sidecar and expose
  call-target lookup by file path, caller QN, and call spelling
- extended `src/pipeline.zig` so unresolved route-registration calls keep their
  existing path, explicit hybrid sidecar hits are preferred ahead of the
  registry, and non-hybrid calls still fall back to the existing resolver
- stored hybrid-sidecar provenance on emitted `CALLS` edges via edge properties
- added `testdata/interop/hybrid-resolution/go-sidecar/` to prove the sidecar
  can override an ambiguous Go method target that the heuristic registry would
  otherwise choose by first match
- fixed `scripts/bootstrap_worktree.sh` so fresh linked worktrees with a
  partially populated `vendored/grammars/` tree do not falsely report success

## Verification

Completed verification on 2026-04-19:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
zig build run -- cli index_repository '{"project_path":"testdata/interop/hybrid-resolution/go-sidecar"}'
zig build run -- cli query_graph '{"project":"go-sidecar","query":"MATCH (a:Function)-[r:CALLS]->(b) RETURN a.qualified_name, b.qualified_name, r.properties_json ORDER BY a.qualified_name, b.qualified_name"}'
```

Observed results:

- `zig build`: pass
- `zig build test`: pass
- fixture-backed CLI probe indexed `go-sidecar` with `13` nodes and `15` edges
- fixture-backed CLI probe returned:
  - `go-sidecar:main.go:go:symbol:go:run`
    ->
    `go-sidecar:workers.go:go:symbol:go:Primary.Handle`
- unit coverage now also proves the no-sidecar fallback path stays operational

## Residual Delta

Still deferred after this plan:

- C/C++ hybrid-resolution coverage
- compile-commands ingestion for hybrid resolution
- live external resolver processes
- any broader language-support expansion beyond this bounded Go-backed slice
