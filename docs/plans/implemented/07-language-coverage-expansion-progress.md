# Language Coverage Expansion Progress

## Scope

This plan broadens parser-backed language coverage with a bounded first tranche
 that improves the product story without reopening hybrid type resolution.

Current focus:
- promote Go from a detected-but-not-parser-backed language into a verified
  tree-sitter-backed language with stable definition and method ownership facts
- add Java as the next parser-backed language because it is a visible original
  language family and does not depend on the deferred hybrid LSP/type layer
- keep the tranche limited to parser-backed discovery, extraction, import
  parsing, and interop fixtures rather than broader type resolution or
  unsupported embedded-script families

## Phase 1 Contract

### Current support reviewed

- parser-backed definitions are currently shipped for:
  - Python
  - JavaScript
  - TypeScript
  - TSX
  - Rust
  - Zig
- broad filename and extension detection already exists for:
  - Go
  - Java
  - many other original language families
- the current interop manifest already contains `go-basic` and `go-parity`, but
  their golden snapshots show empty `search_graph`, `query_graph`, and
  `trace_call_path` results today
- `docs/port-comparison.md` still classifies the full language-support row as
  partial, with only Python, JavaScript, TypeScript/TSX, Rust, and Zig called
  out as parser-backed

### Chosen tranche

- parser-backed Go:
  - function declarations
  - method declarations with receiver ownership
  - struct and interface type definitions
  - import parsing for stable registry and query behavior
- parser-backed Java:
  - class, interface, enum, and record definitions
  - method and constructor definitions with class ownership
  - import parsing for stable registry and query behavior
- fixture surface:
  - upgrade the existing Go fixtures from empty-result diagnostics into verified
    graph facts
  - add a new Java fixture under `testdata/interop/language-expansion/`
  - add extractor unit coverage for Go and Java tree-sitter definitions

### Explicit non-goals for this plan

- hybrid type or LSP resolution for Go, C, or C++
- C++, R, Svelte, or Vue parser-backed expansion
- broader route-framework registration or embedded-script extraction
- full original language breadth in one step

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
python3 - <<'PY' "$tmp_manifest"
import json,sys
from pathlib import Path
manifest=json.loads(Path('testdata/interop/manifest.json').read_text())
keep={'go-basic','go-parity','java-basic'}
manifest['fixtures']=[fx for fx in manifest['fixtures'] if fx['id'] in keep]
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2)+"\n")
PY
bash scripts/run_interop_alignment.sh --zig-only "$tmp_manifest" .interop_reports/lang-expansion
bash scripts/run_interop_alignment.sh "$tmp_manifest" .interop_reports/lang-expansion-compare
```

## Phase 1 Checkpoint: Contract Lock

Plan-start pass on 2026-04-19:

- reviewed the current extractor gate and confirmed tree-sitter support is
  limited to Python, JavaScript, TypeScript, TSX, Rust, and Zig
- confirmed `discover.zig` already recognizes Go and Java, which keeps the
  required work focused on vendoring grammars plus extraction logic
- confirmed the current interop harness already contains Go fixtures whose
  golden snapshots are effectively empty, making Go a clean measurable upgrade
- selected Go and Java as the bounded first tranche because they are visible
  original-language families and do not require the deferred hybrid type layer

Verification for this slice:

```sh
git status --short --branch
sed -n '1,260p' docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md
```

Results:

- worktree confirmed at
  `/Users/skooch/projects/worktrees/language-coverage-expansion`
  on `codex/language-coverage-expansion`
- plan target narrowed to parser-backed Go plus Java rather than a vague
  multi-language sweep

## Phase 2 Checkpoint: Go and Java Parser Support

Implementation completed on 2026-04-19:

- build and vendoring:
  - `build.zig` now compiles Go and Java parsers
  - `scripts/fetch_grammars.sh` now fetches Go and Java grammar sources
  - the worktree now vendors grammar-local `tree_sitter/` headers for both new
    languages, which keeps their generated parsers ABI-compatible with the repo
- extractor support:
  - `src/extractor.zig` now supports Go and Java in
    `supportsTreeSitterDefs`
  - Go tree-sitter extraction now emits functions, methods, structs, and
    interfaces, with receiver ownership mapped onto `DEFINES_METHOD`
  - Java tree-sitter extraction now emits classes, interfaces,
    constructors, and methods with container ownership
  - Go and Java import parsing now feeds the unresolved import layer
- fixture surface:
  - `go-basic` and `go-parity` goldens now capture non-empty graph facts
  - `java-basic` now lives under
    `testdata/interop/language-expansion/java-basic`
  - extractor unit tests now lock Go and Java definitions and ownership

Verification for this slice:

```sh
zig build test
```

Results:

- `zig build test` passed after restoring the shared tree-sitter headers and
  copying the grammar-local `tree_sitter/` directories for Go and Java

## Phase 3 Checkpoint: Verification and Reclassification

Scoped verification completed on 2026-04-19:

```sh
zig build
zig build test
tmp_manifest=$(mktemp)
python3 - <<'PY' "$tmp_manifest"
import json,sys
from pathlib import Path
manifest=json.loads(Path('testdata/interop/manifest.json').read_text())
keep={'go-basic','go-parity','java-basic'}
manifest['fixtures']=[fx for fx in manifest['fixtures'] if fx['id'] in keep]
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2)+"\n")
PY
bash scripts/run_interop_alignment.sh --zig-only "$tmp_manifest" .interop_reports/lang-expansion
bash scripts/run_interop_alignment.sh "$tmp_manifest" .interop_reports/lang-expansion-compare
rm -f "$tmp_manifest"
```

Results:

- `zig build` passed
- `zig build test` passed
- scoped zig-only golden comparison:
  - `go-basic`: pass
  - `go-parity`: pass
  - `java-basic`: pass
- scoped Zig-vs-C comparison:
  - `go-basic`: pass
  - `go-parity`: query-result deltas only
  - `java-basic`: query-result deltas only
- `docs/port-comparison.md` now classifies Go and Java as parser-backed in the
  Zig port while keeping interoperability conservative for those new rows

Verification note outside the plan gate:

- a full-repo `bash scripts/run_interop_alignment.sh --zig-only` run still
  reports unrelated pre-existing harness debt outside this plan:
  - `python-parity` schema-shape drift
  - missing golden snapshots for `discovery-scope`,
    `python-framework-cases`, and `typescript-import-cases`
- those unrelated issues did not block the scoped Go and Java tranche
  verification used to close this plan

Intentional residual delta after completion:

- hybrid type or LSP resolution for Go, C, and C++ remains deferred
- C++, R, Svelte, and Vue parser-backed expansion remain deferred
- the new Go and Java rows are verified Zig-side language additions, but not a
  strict shared-parity claim because scoped Zig-vs-C comparison still has
  query-result deltas
