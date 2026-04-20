# Plan: Near-Parity Protocol Tool Surface

## Goal
Resolve the protocol and public tool-surface rows that are still only `Near parity`
or that block honest promotion of other rows.

## Current Phase
Completed

## File Map
- Modify: `src/mcp.zig`
- Modify: `src/main.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/golden/protocol-contract.json`
- Create: `testdata/interop/golden/tool-surface-parity.json`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/interop-testing-review.md`

## Phases

### Phase 1: Set the exact parity target
- [x] Decide whether tool-surface full parity requires exposing a stub
      `ingest_traces` entry or whether that row remains intentionally below full
      parity.
- [x] Decide whether `index_repository` full parity requires accepting
      `repo_path` and exposing `moderate` mode.
- [x] Record those decisions in `docs/port-comparison.md` before code changes.
- **Status:** completed

### Phase 2: Implement protocol and schema deltas
- [x] Update `src/mcp.zig` `initialize` handling to negotiate supported protocol
      versions instead of returning one fixed version.
- [x] Update `src/mcp.zig` tool schemas and argument aliases for the selected
      parity target, including `repo_path` if adopted.
- [x] Update `src/main.zig` or CLI entry paths if one-shot tool execution needs
      response-shape or argument normalization changes to match the selected
      contract.
- **Status:** completed

### Phase 3: Add exact protocol fixtures
- [x] Extend `scripts/run_interop_alignment.sh` to compare `initialize`,
      `tools/list`, `tools/call`, and one-shot CLI execution at the exact
      protocol-contract layer.
- [x] Add `protocol-contract` and `tool-surface-parity` goldens that lock tool
      inventory, schema keys, protocol versions, and error-code behavior.
- [x] Update `testdata/interop/manifest.json` so these checks run as named
      fixtures instead of ad hoc script logic.
- **Status:** completed

### Phase 4: Reclassify the affected rows
- [x] Promote only the rows that now have both exact behavior and exact
      verification.
- [x] Downgrade any row that still depends on a chosen divergence such as
      omitting `ingest_traces`.
- **Status:** completed

## Verification
- `zig build`
- `zig build test`
- `bash scripts/run_interop_alignment.sh --zig-only`
- `bash scripts/run_interop_alignment.sh`

## Decisions
| Decision | Rationale |
|----------|-----------|
| Put protocol negotiation and tool inventory in one plan | They define the public contract every later parity claim depends on. |
| Require exact fixture coverage here | These rows are too foundational to leave on bounded assertions. |
| Expose `ingest_traces` as a stub | Upstream `v0.6.0` exposes it publicly and returns an accepted-but-unimplemented stub response, so the honest parity target includes the tool entry. |
| Adopt public `repo_path` with `project_path` as a compatibility alias | The public contract should converge on the upstream argument name without breaking existing local fixtures and CLI invocations. |
| Do not advertise `moderate` until the pipeline really supports it | Mapping `moderate` to `full` would hide a real semantic and indexing-mode gap instead of fixing it. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
