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
bash scripts/run_interop_alignment.sh --zig-only
bash scripts/run_interop_alignment.sh
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
