# Plan: Test Tagging Parity

## Goal
Implement the original test-tagging pass so the Zig graph can persist `TESTS` metadata and optionally include tests in higher-level analysis features.

## Current Phase
Completed

## File Map
- Modify: `docs/plans/implemented/test-tagging-parity-plan.md`
- Modify: `docs/plans/implemented/test-tagging-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/test_tagging.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store_test.zig`
- Modify: `src/extractor.zig`
- Modify: `src/root.zig`
- Modify: `scripts/run_interop_alignment.sh`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/test-tagging/python_tests/test_widget.py`
- Create: `testdata/interop/test-tagging/python_tests/widget.py`

## Phases

### Phase 1: Lock the Test-Tagging Contract
- [x] Re-read the original test-tagging pass and capture the overlapping `TESTS` node and edge semantics in `docs/gap-analysis.md`.
- [x] Add local source and test fixtures in `testdata/interop/test-tagging/python_tests/` so test tagging can be verified without external repos.
- [x] Record the target verification workflow and expected graph queries in `docs/plans/in-progress/test-tagging-parity-progress.md`.
- **Status:** completed

### Phase 2: Implement Test Metadata Extraction
- [x] Add `src/test_tagging.zig` to own test-file discovery, test-to-subject matching, and persisted metadata generation.
- [x] Extend `src/pipeline.zig`, `src/store.zig`, `src/store_test.zig`, and `src/extractor.zig` so `TESTS` facts are stored and queryable without regressing the current core graph.
- [x] Add focused regression tests that lock the supported naming and ownership rules for test tagging.
- **Status:** completed

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and direct graph queries against the local test-tagging fixture until the `TESTS` rows are stable.
- [x] Update `docs/port-comparison.md` so the test-tagging rows move out of `Deferred` only after the fixture-backed graph facts are green.
- [x] Record the exact supported test-language and naming rules in `docs/plans/implemented/test-tagging-parity-progress.md`.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start with Python test fixtures | The existing parser-backed Python lane makes it the lowest-risk entry point for proving the `TESTS` contract end to end. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
