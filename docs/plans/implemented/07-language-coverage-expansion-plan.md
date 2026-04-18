# Plan: Language Coverage Expansion

## Goal
Broaden parser-backed language coverage so the Zig port can market itself as closer to the original's breadth instead of as a narrower daily-use subset concentrated in a smaller language set.

## Current Phase
Implemented

## File Map
- Modify: `docs/plans/implemented/07-language-coverage-expansion-plan.md`
- Create: `docs/plans/implemented/07-language-coverage-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/README.md`
- Modify: `CLAUDE.md`
- Modify: `build.zig`
- Modify: `scripts/fetch_grammars.sh`
- Modify: `src/extractor.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/go-basic.json`
- Modify: `testdata/interop/golden/go-parity.json`
- Create: `testdata/interop/golden/java-basic.json`
- Create: `testdata/interop/language-expansion/java-basic/Main.java`
- Create: `vendored/grammars/go/`
- Create: `vendored/grammars/java/`

## Phases

### Phase 1: Lock the Expansion Contract
- [x] Re-read the original language-support surface and identify the next parser-backed languages that most improve the drop-in replacement story in `docs/gap-analysis.md`.
- [x] Define the chosen language rollout, fixture set, and verification workflow in `docs/plans/implemented/07-language-coverage-expansion-progress.md`.
- [x] Keep the first pass limited to concrete parser-backed additions rather than reopening hybrid LSP resolution in the same plan.
- **Status:** complete

### Phase 2: Implement Additional Language Support
- [x] Extend `build.zig`, `scripts/fetch_grammars.sh`, and `src/extractor.zig` so the selected Go and Java languages are discoverable, parsed, and indexed end to end.
- [x] Add local fixtures under `testdata/interop/language-expansion/` and wire them into `testdata/interop/manifest.json`.
- [x] Add focused extraction coverage and scoped interop goldens that lock the supported semantics for each newly added language.
- **Status:** complete

### Phase 3: Verify And Reclassify
- [x] Run `zig build`, `zig build test`, and the scoped language-expansion interop fixture checks until the selected languages index successfully and expose stable graph facts.
- [x] Update `docs/port-comparison.md` so the language-coverage rows reflect the added parser-backed languages without overstating strict shared parity.
- [x] Record the final verification transcript and any intentionally deferred language families in `docs/plans/implemented/07-language-coverage-expansion-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Prioritize parser-backed languages with visible product value | The drop-in replacement story improves faster when new languages are real end-to-end additions rather than thin heuristics. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Added Go and Java parser sources without their grammar-local `tree_sitter/` headers | `zig build test` failed with parser-header ABI errors like `unknown type name 'TSFieldMapSlice'`. | Restored the shared headers, copied the grammar-local `tree_sitter/` directories beside both new parser sources, and recorded the fix path in `CLAUDE.md`. |
