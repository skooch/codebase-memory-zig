# Plan: Language Breadth Expansion

## Goal
Expand parser-backed language breadth beyond the current tranche in a way that stays explicit about which new languages are shared parity claims and which are Zig-only expansion claims.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/11-language-breadth-expansion-plan.md`
- Create: `docs/plans/new/11-language-breadth-expansion-progress.md`
- Modify: `docs/language-support.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `build.zig`
- Modify: `scripts/fetch_grammars.sh`
- Modify: `src/discover.zig`
- Modify: `src/extractor.zig`
- Modify: `src/store_test.zig`
- Modify: `testdata/interop/manifest.json`
- Modify: `testdata/interop/golden/`
- Create: `testdata/interop/language-expansion/`

## Phases

### Phase 1: Choose the next parser-backed tranche
- [ ] Score the next candidate language set against parser availability, verification cost, and parity value, using a concrete shortlist rather than an open-ended breadth wish list.
- [ ] Select one coherent next tranche and record which languages are intended as shared parity targets versus Zig-only expansion targets.
- [ ] Write the selected tranche and exact fixture targets into `docs/plans/in-progress/11-language-breadth-expansion-progress.md`.
- **Status:** pending

### Phase 2: Add the next language tranche
- [ ] Extend `build.zig`, `scripts/fetch_grammars.sh`, `src/discover.zig`, and `src/extractor.zig` for the selected language tranche.
- [ ] Add store-level coverage and fixture-backed interop cases under `testdata/interop/language-expansion/`.
- [ ] Refresh only the affected manifest assertions and goldens after the chosen tranche is green in its intended verification mode.
- **Status:** pending

### Phase 3: Rebaseline language-support claims
- [ ] Re-run the build, test, and interop verification required for the selected language tranche.
- [ ] Update `docs/language-support.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so they state the new language-support claim level precisely.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the selected tranche is fully documented from measured evidence.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Choose one concrete tranche before changing the build | Language breadth is too large to execute safely without an explicit shortlist. |
| Keep shared-parity and Zig-only claims separate | The docs already rely on that distinction to stay honest. |
| Make fixture cost part of tranche selection | Parser breadth only matters if the new language can be verified cleanly. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
