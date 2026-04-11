# Plan: Test Tagging Parity

## Goal
Implement the original test-tagging pass so the Zig graph can persist `TESTS` metadata and optionally include tests in higher-level analysis features.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/test-tagging-parity-plan.md`
- Create: `docs/plans/new/test-tagging-parity-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Create: `src/test_tagging.zig`
- Modify: `src/pipeline.zig`
- Modify: `src/store.zig`
- Modify: `src/store_test.zig`
- Modify: `src/extractor.zig`
- Create: `testdata/interop/test-tagging/python_tests/test_widget.py`
- Create: `testdata/interop/test-tagging/python_tests/widget.py`

## Phases

### Phase 1: Lock the Test-Tagging Contract
- [ ] Re-read the original test-tagging pass and capture the overlapping `TESTS` node and edge semantics in `docs/gap-analysis.md`.
- [ ] Add local source and test fixtures in `testdata/interop/test-tagging/python_tests/` so test tagging can be verified without external repos.
- [ ] Record the target verification workflow and expected graph queries in `docs/plans/new/test-tagging-parity-progress.md`.
- **Status:** pending

### Phase 2: Implement Test Metadata Extraction
- [ ] Add `src/test_tagging.zig` to own test-file discovery, test-to-subject matching, and persisted metadata generation.
- [ ] Extend `src/pipeline.zig`, `src/store.zig`, `src/store_test.zig`, and `src/extractor.zig` so `TESTS` facts are stored and queryable without regressing the current core graph.
- [ ] Add focused regression tests that lock the supported naming and ownership rules for test tagging.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and direct graph queries against the local test-tagging fixture until the `TESTS` rows are stable.
- [ ] Update `docs/port-comparison.md` so the test-tagging rows move out of `Deferred` only after the fixture-backed graph facts are green.
- [ ] Record the exact supported test-language and naming rules in `docs/plans/new/test-tagging-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start with Python test fixtures | The existing parser-backed Python lane makes it the lowest-risk entry point for proving the `TESTS` contract end to end. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
