# Progress

## Session: 2026-04-19

### Phase 1: Define the next shared config and edge contract
- **Status:** completed
- Actions:
  - Created the config normalization and `WRITES` / `READS` contract plan as the fifth queued follow-on.
  - Scoped it around proving the next shared contract tranche instead of assuming that all read/write semantics already overlap.
  - Probed both implementations directly on the existing `edge-parity` fixture and on a controlled local-state Python micro-case; both returned zero `WRITES` and zero `READS` rows.
  - Probed additional config-key shapes and confirmed that YAML hyphenated and camel keys have stable shared overlap, while the attempted JSON probe did not produce a stable shared config contract.
  - Chose the next bounded contract tranche as:
    - strict shared YAML key-shape config linking for `api-base-url` and `apiBaseUrl`
    - bounded shared zero-row `WRITES` / `READS` contract on the local-state micro-case
  - Left broader positive `WRITES` / `READS` overlap documented as unproven rather than promoting it without evidence.
- Files modified:
  - `docs/plans/in-progress/05-config-normalization-and-reads-writes-contract-plan.md`
  - `docs/plans/in-progress/05-config-normalization-and-reads-writes-contract-progress.md`

### Phase 2: Expand config normalization and edge extraction
- **Status:** completed
- Actions:
  - Added the new shared config fixture `config-expansion-yaml-key-shapes` with a YAML key-shape case covering both hyphenated and camel config names.
  - Extended the public interop manifest so the new config fixture asserts the shared `CONFIGURES` rows and the edge-parity fixture now explicitly queries `WRITES` and `READS`.
  - Added Zig regression coverage in `src/pipeline.zig` for YAML key-shape config linking and in `src/store_test.zig` for both the config fixture and the bounded zero-row `WRITES` / `READS` contract.
  - Added the explicit local-state edge micro-case file under `testdata/interop/edge-parity/` so the zero-row read/write contract is exercised in the public harness.
- Files modified:
  - `src/pipeline.zig`
  - `src/store_test.zig`
  - `testdata/interop/manifest.json`
  - `testdata/interop/config-expansion/yaml_key_shapes/`
  - `testdata/interop/edge-parity/read_write_local_state.py`

### Phase 3: Rebaseline docs and interop evidence
- **Status:** completed
- Actions:
  - Re-ran `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Verified the new baseline at `31` fixtures, `237` comparisons, `135` strict matches, `35` diagnostic-only comparisons, and `1` remaining mismatch (`go-parity/query_graph`).
  - Confirmed that the new config fixture is a strict shared match and that the new `WRITES` / `READS` queries are strict shared zero-row matches on the bounded edge micro-case.
  - Updated the comparison docs and backlog index to reflect that the queued plan inventory is now fully exhausted.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`
  - `testdata/interop/golden/config-expansion-yaml-key-shapes.json`
  - `testdata/interop/golden/edge-parity.json`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
