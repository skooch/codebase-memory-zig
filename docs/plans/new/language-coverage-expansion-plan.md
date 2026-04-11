# Plan: Language Coverage Expansion

## Goal
Broaden parser-backed definition coverage beyond the current target languages and reduce reliance on fallback heuristics for languages the original already parses deeply.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/language-coverage-expansion-plan.md`
- Create: `docs/plans/new/language-coverage-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `build.zig`
- Modify: `build.zig.zon`
- Modify: `src/discover.zig`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Create: `docs/language-support.md`
- Create: `testdata/interop/go-definitions/main.go`
- Create: `testdata/interop/c-definitions/main.c`
- Create: `testdata/interop/cpp-definitions/main.cpp`

## Phases

### Phase 1: Lock the Expansion Tranche
- [ ] Re-read the original language-support surface and define the first concrete parser-expansion tranche in `docs/gap-analysis.md` and `docs/zig-port-plan.md`.
- [ ] Add local Go, C, and C++ definition fixtures in `testdata/interop/` so future parser work has an exact verification target from the start.
- [ ] Document the tranche scope, skipped languages, and verification commands in `docs/plans/new/language-coverage-expansion-progress.md`.
- **Status:** pending

### Phase 2: Wire New Parser-Backed Definitions
- [ ] Extend `build.zig`, `build.zig.zon`, and `src/discover.zig` so the new parser inputs are vendored, built, and selected deterministically.
- [ ] Broaden `src/extractor.zig` and `src/pipeline.zig` so the new languages produce parser-backed definition inventories instead of falling back to heuristics on the added fixtures.
- [ ] Add `docs/language-support.md` to document exactly which languages are parser-backed, which remain heuristic, and what verification protects each lane.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and fixture-level parity checks for the new language tranche until the definition rows are stable.
- [ ] Update `docs/port-comparison.md` so the full-language-support and heuristic-fallback rows move only as far as the verified tranche justifies.
- [ ] Record remaining unsupported languages and the next tranche entrypoint in `docs/plans/new/language-coverage-expansion-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Start with Go, C, and C++ for the first tranche | Those languages align with the most obvious remaining parity claims and set up the later hybrid-resolution work. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
