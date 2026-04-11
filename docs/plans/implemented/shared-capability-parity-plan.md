# Plan: Shared Capability Parity and Interoperability

## Goal
Bring every currently shared-but-not-interoperable capability in `docs/port-comparison.md` up to full parity with `codebase-memory-mcp`, then update the comparison docs to mark those rows as interoperable.

## Current Phase
Completed

## File Map
- Modify: `docs/plans/implemented/shared-capability-parity-plan.md`
- Modify: `docs/plans/implemented/shared-capability-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `build.zig`
- Modify: `build.zig.zon`
- Modify: `src/mcp.zig`
- Modify: `src/cypher.zig`
- Modify: `src/store.zig`
- Modify: `src/graph_buffer.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/extractor.zig`
- Modify: `src/registry.zig`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/python-parity/main.py`
- Create: `testdata/interop/python-parity/models.py`
- Create: `testdata/interop/python-parity/settings.yaml`
- Create: `testdata/interop/javascript-parity/index.js`
- Create: `testdata/interop/javascript-parity/package.json`
- Create: `testdata/interop/typescript-parity/index.ts`
- Create: `testdata/interop/typescript-parity/tsconfig.json`
- Create: `testdata/interop/rust-parity/src/lib.rs`
- Create: `testdata/interop/rust-parity/Cargo.toml`

## Phases

### Phase 1: Lock the Full-Parity Contract and Verification Surface
- [x] Re-read `docs/port-comparison.md` and extract the exact shared-but-not-interoperable rows this plan is responsible for: `tools/list`, CLI progress output, `query_graph`, `get_architecture`, `search_code`, `detect_changes`, definitions extraction, call resolution, usage/type-reference edges, semantic edges, `CONFIGURES` / `WRITES`, `USES_TYPE`, `install`, `uninstall`, `update`, and auto-detected agent integrations.
- [x] Rewrite the affected sections in `docs/gap-analysis.md` so each targeted row has an explicit full-parity acceptance rule, not just a high-level status label.
- [x] Update `docs/zig-port-plan.md` so the parity objective for this follow-on plan is documented as “close the shared-surface full-parity gaps” rather than “expand the target contract.”
- [x] Extend `testdata/interop/manifest.json` and `scripts/run_interop_alignment.sh` so the harness compares advanced-tool outputs (`tools/list`, `query_graph`, `get_architecture`, `search_code`, `detect_changes`) instead of only the first-gate tool set.
- [x] Add parity fixture repos at `testdata/interop/python-parity/`, `testdata/interop/javascript-parity/`, `testdata/interop/typescript-parity/`, and `testdata/interop/rust-parity/` that deliberately exercise aliasing, type references, semantic edges, config-write edges, and code-search ranking cases needed by later phases.
- **Status:** completed

### Phase 2: Bring the MCP Query and Protocol Surface to Full Parity
- [x] Update `src/mcp.zig` so `tools/list` advertises the full overlapping implemented tool surface with the same tool-level visibility the original exposes for shared features.
- [x] Expand `src/main.zig` and `src/mcp.zig` so `cli --progress` emits the richer phase-aware progress events needed to match the original shared progress contract for overlapping commands.
- [x] Extend `src/cypher.zig`, `src/store.zig`, and `src/mcp.zig` so `query_graph` covers the original overlapping read-only Cypher shapes this repo currently marks as partial, including the query forms needed by `get_architecture`, `search_code`, and `detect_changes`.
- [x] Broaden `src/mcp.zig` output shaping for `get_architecture`, `search_code`, and `detect_changes` so their payload richness, ranking/dedup behavior, and summary fields match the original for shared capabilities instead of the current narrower daily-use summaries.
- [x] Add or extend regression coverage in `src/mcp.zig`, `src/cypher.zig`, and `src/store.zig` for the upgraded contracts, then wire the new harness assertions in `scripts/run_interop_alignment.sh` to fail when the Zig payload shape drifts from the original.
- **Status:** completed

### Phase 3: Bring Shared Graph Construction and Edge Semantics to Full Parity
- [x] Expand `src/extractor.zig`, `src/pipeline.zig`, and `src/registry.zig` so definitions extraction on already-overlapping target languages matches the original’s shared behavior for nested declarations, aliases, and symbol-role labeling rather than stopping at the current daily-use subset.
- [x] Extend `src/registry.zig` and `src/pipeline.zig` so call resolution reaches the original shared overlap for alias-heavy imports, cross-file suffix matches, and the currently missing resolution cases that still force `Partial` status.
- [x] Upgrade `src/extractor.zig`, `src/pipeline.zig`, `src/store.zig`, and `src/graph_buffer.zig` so `USAGE`, type-reference, semantic-edge, `CONFIGURES`, `WRITES`, and `USES_TYPE` behavior match the original overlapping graph contract rather than the current approximations.
- [x] Add the necessary parser/build integration changes in `build.zig` and `build.zig.zon` only where the extractor work requires new vendored parser inputs for already-overlapping language behavior, and keep the phase scoped away from entirely new subsystems such as route graphs or UI.
- [x] Add direct regression coverage in `src/extractor.zig`, `src/pipeline.zig`, `src/registry.zig`, and `src/store.zig`, then expand `testdata/interop/manifest.json` and `scripts/run_interop_alignment.sh` so the new parity fixtures prove the upgraded graph facts against the original implementation.
- **Status:** completed

### Phase 4: Bring CLI and Productization Overlap to Full Parity
- [x] Extend `src/cli.zig` and `src/main.zig` so `install`, `uninstall`, and `update` match the original overlapping workflow expectations for shared agent targets, reporting, and persisted config handling instead of the current narrower source-build path.
- [x] Expand `src/cli.zig` agent detection so the auto-detected integration surface matches the original wherever the underlying agent config format is already supported by the Zig repo, and document any truly unsupported targets as out-of-scope only if they are no longer counted as shared capability rows.
- [x] Preserve the current temp-HOME-safe testing approach while broadening `src/cli.zig` tests to cover the parity-level install, uninstall, update, detection, and reporting behavior this plan is targeting.
- [x] Add manual verification commands and, where practical, scripted checks that compare Zig CLI output against the original for overlapping installer/config flows without touching live user config.
- **Status:** completed

### Phase 5: Close the Loop with Full-Parity Verification and Documentation
- [x] Re-run `zig build`, `zig build test`, and the expanded `bash scripts/run_interop_alignment.sh` against the new parity fixtures until every targeted shared row has a concrete green verification path.
- [x] Run the temp-HOME CLI parity checks for `install`, `uninstall`, `update`, agent detection, and `cli --progress`, and record the exact commands and outcomes in the final plan/progress notes.
- [x] Update `docs/port-comparison.md` so every row targeted by this plan flips to `Interoperable? Yes` only after the corresponding verification evidence exists.
- [x] Refresh `docs/gap-analysis.md` and `docs/zig-port-plan.md` to remove the completed shared-surface parity gaps while leaving still-missing subsystems such as `manage_adr`, route graphs, UI, and test-tagging explicitly outside this plan.
- [x] Move this plan from `docs/plans/new/` to `docs/plans/in-progress/` before implementation starts, then to `docs/plans/implemented/` only after every verification item above is complete.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Scope this plan to capabilities that exist in both implementations but are still marked `Interoperable? No` | This matches the user request and avoids mixing shared-surface parity work with entirely missing subsystems like UI, route graphs, or `manage_adr`. |
| Use one cross-cutting plan instead of separate query, graph, and CLI plans | The same docs, fixtures, and interoperability harness need to prove all three workstreams, so splitting too early would duplicate the verification contract. |
| Treat `docs/port-comparison.md` as an acceptance ledger, not just an outcome report | The new `Interoperable?` column is only trustworthy if each `Yes` maps back to an explicit verification path in the plan and harness. |
| Keep parser/build changes limited to already-overlapping language behavior | The goal is full parity for shared capabilities, not a new commitment to port every original subsystem or all 66-language extraction paths in this plan. |
| Run each interop fixture in an isolated temp runtime for both implementations | The parity harness must compare fixture behavior, not whatever projects happen to be cached in the developer's local Zig or C runtime state. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Expanded `bash scripts/run_interop_alignment.sh` validation did not complete promptly after adding the new parity fixtures; the on-disk report remained at the old 5-fixture baseline. | Reproduced the stall with direct MCP requests, then sampled the Zig server while a second request was pending and confirmed `src/mcp.zig` `runFiles` had fallen back to waiting for another line instead of consuming the second JSON-RPC request. | Resolved for the current harness surface by replacing `runFiles` with an explicit newline-framed file read loop and isolating both implementations in per-fixture temp runtimes. The harness now completes against all 9 fixtures and surfaces real parity mismatches instead of transport/cache artifacts. |
