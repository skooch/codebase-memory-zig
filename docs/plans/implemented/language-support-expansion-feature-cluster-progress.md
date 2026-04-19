# Language Support Expansion Progress

## Scope

Chosen first tranche:
- PowerShell
- GDScript

Deferred next candidate:
- QML

Selection basis for this tranche:
- parser availability exists today with maintained tree-sitter grammars
- declaration shapes are simple enough to wire into the current extractor
  without reopening broader semantic work
- verification cost fits the current repo: parser-backed definition extraction,
  basic search visibility, and fixture-backed indexing checks

Reasons QML is deferred in this tranche:
- the grammar is available, but the first useful contract is already
  object-model-oriented with properties, signals, inline components, and QML/JS
  boundary behavior
- that makes the initial support slice less like "add one parser" and more like
  "define a new semantic posture," which is a worse fit for this bounded plan

## Phase 1 Queue

Scored queue recorded for this branch:
- PowerShell
  - demand: high
  - parser availability: high
  - overlap with current Zig goals: high
  - verification cost: low
- GDScript
  - demand: medium
  - parser availability: high
  - overlap with current Zig goals: medium
  - verification cost: low
- QML
  - demand: medium
  - parser availability: medium
  - overlap with current Zig goals: medium
  - verification cost: medium-high

## Planned Verification

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/powershell-basic"}'
zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/gdscript-basic"}'
```

## Phase 1 Checkpoint: Tranche Selection

Recorded on 2026-04-19:

- activated the dedicated `codex/language-support-expansion` worktree
- retried the graph path once, confirmed `codebase-memory-mcp` still fails with
  `Transport closed`, and continued with local inspection
- selected PowerShell and GDScript as the first parser-backed tranche
- explicitly deferred QML to the next candidate lane instead of mixing a
  heavier object-model language into the same onboarding slice

## Phase 2 Checkpoint: Implementation

Implemented on 2026-04-19:

- added pinned PowerShell and GDScript grammar fetches to
  `scripts/fetch_grammars.sh`
- fixed `scripts/fetch_grammars.sh` for the macOS Bash 3.2 environment by
  replacing associative arrays with portable `case` helpers
- added PowerShell and GDScript parser wiring to `build.zig`
- added `.ps1`, `.psm1`, `.psd1`, and `.gd` detection to `src/discover.zig`
- added tree-sitter-backed PowerShell and GDScript definition extraction to
  `src/extractor.zig`
- added fixture-backed store coverage for both new languages in
  `src/store_test.zig`
- documented the repo’s support taxonomy in `docs/language-support.md`

## Phase 3 Checkpoint: Verification

Completed on 2026-04-19:

- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
- `bash scripts/fetch_grammars.sh --force`
- `zig build`
- `zig build test`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/powershell-basic"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli query_graph '{"project":"powershell-basic","query":"MATCH (n) WHERE n.file_path = \"main.ps1\" RETURN n.label, n.name ORDER BY n.label, n.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli index_repository '{"project_path":"testdata/interop/language-expansion/gdscript-basic"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/language-support-expansion/.cbm-cache-verify zig build run -- cli query_graph '{"project":"gdscript-basic","query":"MATCH (n) WHERE n.file_path = \"main.gd\" RETURN n.label, n.name ORDER BY n.label, n.name"}'`

Observed results:

- PowerShell fixture indexed `6` nodes and `6` edges
- PowerShell query returned `Class Worker`, `Function Invoke-Users`, and
  `Method Run`
- GDScript fixture indexed `7` nodes and `7` edges
- GDScript query returned `Class Hero`, `Class Worker`, `Function boot`, and
  `Method run`

Next deferred candidate after completion:
- QML
