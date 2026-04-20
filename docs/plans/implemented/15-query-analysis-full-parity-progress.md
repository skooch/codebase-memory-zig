# Progress: Near-Parity Query Analysis Contracts

## 2026-04-21

- Moved the plan into active execution and confirmed the scoped rows for this
  slice: `query_graph`, `trace_call_path`, `get_code_snippet`,
  `get_graph_schema`, `get_architecture`, `search_code`, `list_projects`,
  `delete_project`, `index_status`, and `manage_adr`.
- Extended `scripts/run_interop_alignment.sh` so the compare harness can score
  exact or canonicalized contract parity for these rows instead of only bounded
  assertion floors.
- Added named fixture coverage and committed goldens for:
  - `snippet-trace-contract`
  - `architecture-aspects-parity`
  - `search-code-ranking-parity`
- Tightened `query_graph` exactness through the expanded
  `cypher-predicate-floor` fixture coverage, including boolean-precedence,
  count/distinct, path-shape, and numeric predicate cases already exercised by
  the manifest.
- Fixed the real Zig behavioral deltas exposed by the new exact fixtures:
  - `trace_call_path` now defaults `include_tests` to the upstream `false`
    contract and emits the upstream-style start-centered `edges` view.
  - `get_code_snippet` now resolves basename-style suffix lookups such as
    `main.entry`.
  - `search_code` now handles grouped alternation patterns, dedupes full-mode
    results by containing symbol, emits full-mode `source`, uses upstream-style
    files-mode output, and aligns module span reporting with the reference
    implementation.
- Kept canonicalization limited to representation-only differences:
  - `search_code` compare mode now treats `source` vs `snippet` as one
    comparable field.
  - `get_architecture` and `get_graph_schema` stay diagnostic-only where the
    shared summary/schema contract matches but payload richness still differs.
- Reclassified the docs using the measured fixture evidence:
  - `query_graph`, `trace_call_path`, `get_code_snippet`, `search_code`,
    `list_projects`, `delete_project`, `index_status`, and `manage_adr` now
    count as fully verified shared rows.
  - `get_architecture` and `get_graph_schema` stay on the shared-contract floor
    with diagnostic exactness rather than payload-identity claims.
- Final verification for this plan:
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/run_interop_alignment.sh --update-golden`: pass
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`38/38`)
  - `bash scripts/run_interop_alignment.sh`: pass with `38` fixtures, `294`
    comparisons, `161` strict matches, `44` diagnostic-only comparisons, `0`
    mismatches, and `cli_progress: match`
