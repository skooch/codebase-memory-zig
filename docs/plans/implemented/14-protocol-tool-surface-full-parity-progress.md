# Progress: Near-Parity Protocol Tool Surface

## 2026-04-20

- Moved the plan into `docs/plans/in-progress/` and updated the queue to treat
  this as the active execution slice.
- Confirmed from `codebase-memory-mcp` `v0.6.0` that protocol negotiation is
  version-selecting, `tools/list` includes a visible `ingest_traces` stub,
  `index_repository` publicly uses `repo_path`, and its schema advertises
  `full`, `moderate`, and `fast`.
- Confirmed in Zig that `src/mcp.zig` still hardcodes protocol version
  `2025-06-18`, still advertises `project_path`, still omits `ingest_traces`,
  and only supports `full` / `fast`.
- Selected phase-1 decisions:
  - `ingest_traces` should be exposed as an explicit stub because upstream also
    exposes it as a public stub and the tool inventory is part of the contract.
  - `repo_path` should become the public argument name, while `project_path`
    remains a backward-compatible alias.
  - `moderate` should not be advertised until Zig has a real moderate-mode
    implementation; this row must stay below full parity until the pipeline
    work exists.
- Current implementation slice:
  - protocol negotiation in `initialize`
  - `repo_path` compatibility across MCP and one-shot CLI progress
  - upstream-style `ingest_traces` stub exposure
  - parity docs updated to stop overclaiming `tools/list` and
    `index_repository`
- Completed implementation details:
  - `src/mcp.zig` now negotiates supported protocol versions instead of always
    returning `2025-06-18`.
  - `src/mcp.zig` now exposes `ingest_traces` in `tools/list` and returns an
    accepted stub response for `tools/call`.
  - `src/mcp.zig` now uses public `repo_path` while still accepting
    `project_path` as a compatibility alias.
  - `src/main.zig` CLI progress now accepts both `repo_path` and the older
    `project_path` alias.
- Verification:
  - `zig build test`: pass
  - `zig build`: pass
  - `bash scripts/run_interop_alignment.sh --update-golden`: pass
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`33/33`)
  - `bash scripts/run_interop_alignment.sh`: pass with `0` mismatches
- Follow-on work left in this plan:
  - add exact protocol-contract fixtures instead of relying on the existing
    broader `tools_list` golden snapshots
  - decide whether `tools/list` and `index_repository` stay downgraded until a
    real `moderate` indexing mode exists

## 2026-04-21

- Completed the exact protocol-contract fixture layer in
  `scripts/run_interop_alignment.sh` and `testdata/interop/manifest.json`.
- Added named fixtures and committed goldens for:
  - `protocol-contract`
  - `tool-surface-parity`
- Locked exact public-contract coverage for:
  - `initialize` protocol-version negotiation
  - `tools/list` inventory and selected schema keys
  - `tools/call` behavior for the shared protocol layer, including the public
    `ingest_traces` stub
  - one-shot CLI tool execution at the exact contract layer
- Reclassified the affected parity docs using the measured fixture evidence:
  - `initialize`, `tools/call`, and one-shot CLI execution stay promotable as
    verified shared rows
  - `tools/list` stays `Partial`
  - `index_repository` stays `Partial`
  - the remaining blocker is the missing latest-upstream `moderate` mode, not
    any longer a protocol-plumbing gap
- Final verification for this plan:
  - `zig build`: pass
  - `zig build test`: pass
  - `bash scripts/run_interop_alignment.sh --update-golden`: pass
  - `bash scripts/run_interop_alignment.sh --zig-only`: pass (`35/35`)
  - `bash scripts/run_interop_alignment.sh`: pass with `35` fixtures, `267`
    comparisons, `150` strict matches, `39` diagnostic-only comparisons, `0`
    mismatches, and `cli_progress: match`
- Final contract result:
  - `protocol-contract`: strict shared match
  - `tool-surface-parity`: diagnostic-only by design because Zig still rejects
    `index_repository(mode="moderate")` while the latest upstream release
    accepts it
