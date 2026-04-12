# Plan: Language Coverage Expansion

## Goal
Broaden parser-backed language coverage so the Zig port can market itself as closer to the original's breadth instead of as a narrower daily-use subset concentrated in a smaller language set.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md`
- Create: `docs/plans/new/ready-to-go/07-language-coverage-expansion-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `build.zig`
- Modify: `build.zig.zon`
- Modify: `src/extractor.zig`
- Modify: `src/discover.zig`
- Modify: `src/pipeline.zig`
- Modify: `testdata/interop/manifest.json`
- Create: `testdata/interop/language-expansion/`

## Phases

### Phase 1: Lock the Expansion Contract
- [ ] Re-read the original language-support surface and identify the next parser-backed languages that most improve the drop-in replacement story in `docs/gap-analysis.md`.
- [ ] Define the chosen language rollout, fixture set, and verification workflow in `docs/plans/new/ready-to-go/07-language-coverage-expansion-progress.md`.
- [ ] Keep the first pass limited to concrete parser-backed additions rather than reopening hybrid LSP resolution in the same plan.
- **Status:** pending

### Phase 2: Implement Additional Language Support
- [ ] Extend `build.zig`, `build.zig.zon`, `src/discover.zig`, `src/extractor.zig`, and `src/pipeline.zig` so the next selected languages are discoverable, parsed, and indexed end to end.
- [ ] Add local fixtures under `testdata/interop/language-expansion/` and wire them into `testdata/interop/manifest.json`.
- [ ] Add focused extraction and pipeline coverage that locks the supported semantics for each newly added language.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `zig build test`, and the language-expansion interop fixture checks until the selected languages index successfully and expose stable graph facts.
- [ ] Update `docs/port-comparison.md` so the language-coverage rows move out of `Partial` only after the added parser-backed languages are verified.
- [ ] Record the final verification transcript and any intentionally deferred language families in `docs/plans/new/ready-to-go/07-language-coverage-expansion-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Prioritize parser-backed languages with visible product value | The drop-in replacement story improves faster when new languages are real end-to-end additions rather than thin heuristics. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
