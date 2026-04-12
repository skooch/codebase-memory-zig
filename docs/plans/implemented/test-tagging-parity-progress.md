# Progress

## Session: 2026-04-11

### Phase 1: Lock the Test-Tagging Contract
- **Status:** completed
- Actions:
  - Moved `docs/plans/new/test-tagging-parity-plan.md` to `docs/plans/in-progress/test-tagging-parity-plan.md` before implementation so the active work follows the repo's plan convention.
  - Re-read the original `pass_tests.c` contract and confirmed the overlapping Zig target is a derived pass that adds `TESTS` from existing `CALLS` edges and `TESTS_FILE` from shared filename rules, without reopening wider language-specific ownership work.
  - Locked the first verification slice to local Python fixtures plus direct graph queries so the parity evidence stays reproducible inside this repo.
- Verification target:
  - `zig build`
  - `zig build test`
  - `bash scripts/run_interop_alignment.sh`
  - `zig build run -- cli query_graph '{"project":"test-tagging","query":"MATCH (a)-[r:TESTS]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC","max_rows":20}'`
- Expected graph queries:
  - `MATCH (a)-[r:TESTS]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC`
  - `MATCH (a)-[r:TESTS_FILE]->(b) RETURN a.name, b.name ORDER BY a.name ASC, b.name ASC`
- Files modified:
  - `docs/plans/implemented/test-tagging-parity-plan.md`
  - `docs/plans/implemented/test-tagging-parity-progress.md`

### Phase 2: Implement Test Metadata Extraction
- **Status:** completed
- Actions:
  - Started the dedicated `src/test_tagging.zig` pass to keep test-path and test-name heuristics in one place instead of hiding them inside `src/pipeline.zig`.
  - Added the `test_tagging` pass after edge resolution so Zig now derives shared `TESTS` and `TESTS_FILE` edges from existing `CALLS` edges and shared filename rules instead of leaving the original `pass_tests.c` contract unimplemented.
  - Added focused regression coverage in `src/pipeline.zig`, `src/store_test.zig`, and `src/test_tagging.zig` to lock the supported Python naming rules and file-pair mapping behavior.
  - Retained file-level `is_test` metadata on exercised test files; symbol-level `is_test` persistence remains outside the accepted shared slice for this plan.
- Files modified:
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `src/root.zig`
  - `src/store_test.zig`
  - `src/test_tagging.zig`
  - `testdata/interop/test-tagging/python_tests/test_widget.py`
  - `testdata/interop/test-tagging/python_tests/widget.py`

### Phase 3: Verify and Reclassify
- **Status:** completed
- Actions:
  - Added the local `test-tagging` fixture to `testdata/interop/manifest.json` so the interop harness now compares the shared `TESTS` and `TESTS_FILE` query rows against the original implementation.
  - Re-ran the required verification:
    - `zig build` → passed
    - `zig build test` → passed
    - `bash scripts/run_interop_alignment.sh` → passed with `0` mismatches and `query_graph: match` on the `test-tagging` fixture
    - direct MCP session against `./zig-out/bin/cbm` → returned `["test_widget_renders","render_widget"]` for `TESTS` and `["test_widget.py","widget.py"]` for `TESTS_FILE`
  - Updated `docs/port-comparison.md` and `docs/gap-analysis.md` so the shared test-tagging slice is now treated as implemented while broader git-history and config-link follow-ons remain deferred.
- Supported rules:
  - `TESTS` edges are derived from existing `CALLS` edges only when the caller is in a test-shaped file and the caller name follows the shared test-function naming rules.
  - `TESTS_FILE` edges currently cover the shared Python `test_*.py -> *.py` naming lane verified by the local fixture, with the helper module also preserving the original overlap for `_test.go` and `.test/.spec` JavaScript or TypeScript filenames.
- Files modified:
  - `docs/gap-analysis.md`
  - `docs/plans/implemented/test-tagging-parity-plan.md`
  - `docs/plans/implemented/test-tagging-parity-progress.md`
  - `docs/port-comparison.md`
  - `testdata/interop/manifest.json`
