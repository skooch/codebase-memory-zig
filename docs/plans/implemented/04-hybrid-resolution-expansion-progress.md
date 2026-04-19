# Progress

## Session: 2026-04-20

### Phase 1: Define the next hybrid-resolution target
- **Status:** completed
- Actions:
  - Created the hybrid-resolution expansion plan as backlog item `04`.
  - Scoped it to one explicit next ambiguity slice rather than a broad “finish hybrid resolution” umbrella.
  - Reviewed the current sidecar implementation and selected the next bounded target as an expanded Go-only slice rather than a premature C/C++ micro-case.
  - Chose a stable deterministic contract that does not require a live external resolver:
    - multiple caller documents
    - sidecar `language: "golang"` alias support
    - `callee_name` fallback when `full_callee_name` is absent
  - Confirmed the existing `go-sidecar` fixture already compares cleanly against the C reference, so the expanded slice could be promoted into the shared harness instead of staying Zig-only.
- Files modified:
  - `docs/plans/implemented/04-hybrid-resolution-expansion-plan.md`
  - `docs/plans/implemented/04-hybrid-resolution-expansion-progress.md`

### Phase 2: Extend sidecar-backed resolution
- **Status:** completed
- Actions:
  - Extended `src/hybrid_resolution.zig` to accept the sidecar language alias `golang` in addition to `go`.
  - Added `go-sidecar-expanded` under `testdata/interop/hybrid-resolution/` with:
    - one caller in `main.go`
    - one caller in `extras.go`
    - explicit sidecar resolutions for both callers
    - one resolution that depends on `callee_name` fallback instead of `full_callee_name`
  - Added pipeline and store regressions that verify the sidecar strategy is persisted on both caller paths and that the resolved call targets are the intended Go methods.
  - Added a shared interop fixture assertion for the expanded slice using the public `a.name, b.name` call-edge contract, which both Zig and C match.
- Files modified:
  - `src/hybrid_resolution.zig`
  - `src/pipeline.zig`
  - `src/store_test.zig`
  - `testdata/interop/hybrid-resolution/go-sidecar-expanded/`
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/`

### Phase 3: Rebaseline hybrid-resolution claims
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Measured the new full-compare baseline at:
    - `33` fixtures
    - `251` comparisons
    - `143` strict matches
    - `38` diagnostic-only comparisons
    - `0` mismatches
    - `cli_progress: match`
  - Updated the comparison docs so the hybrid-resolution row now explicitly reflects the expanded bounded Go sidecar contract while keeping C/C++ and live LSP integration deferred.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
