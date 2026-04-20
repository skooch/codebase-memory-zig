# Plan: Language Breadth Expansion

## Goal
Expand parser-backed language breadth beyond the current tranche in a way that stays explicit about which new languages are shared parity claims and which are Zig-only expansion claims.

## Current Phase
Complete

## File Map
- Modify: `docs/language-support.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/README.md`
- Modify: `build.zig`
- Modify: `scripts/fetch_grammars.sh`
- Modify: `src/extractor.zig`
- Modify: `src/store_test.zig`
- Create: `testdata/interop/language-expansion/csharp-basic/Program.cs`
- Move: `docs/plans/in-progress/11-language-breadth-expansion-plan.md` -> `docs/plans/implemented/11-language-breadth-expansion-plan.md`
- Move: `docs/plans/in-progress/11-language-breadth-expansion-progress.md` -> `docs/plans/implemented/11-language-breadth-expansion-progress.md`

## Phases

### Phase 1: Choose the next parser-backed tranche
- [x] Score the next candidate language set against parser availability, verification cost, and parity value, using a concrete shortlist rather than an open-ended breadth wish list.
- [x] Select one coherent next tranche and record which languages are intended as shared parity targets versus Zig-only expansion targets.
- [x] Write the selected tranche and exact fixture targets into the paired progress log.
- **Status:** complete

### Phase 2: Add the next language tranche
- [x] Extend the parser build and extraction path for the selected language tranche.
- [x] Add store-level coverage and fixture-backed language-expansion checks under `testdata/interop/language-expansion/`.
- [x] Refresh only the affected documented evidence after the chosen tranche is green in its intended verification mode.
- **Status:** complete

### Phase 3: Rebaseline language-support claims
- [x] Re-run the build, test, and direct verification required for the selected language tranche.
- [x] Update `docs/language-support.md`, `docs/port-comparison.md`, and `docs/gap-analysis.md` so they state the new language-support claim level precisely.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the selected tranche is fully documented from measured evidence.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Choose one concrete tranche before changing the build | Language breadth is too large to execute safely without an explicit shortlist. |
| Keep shared-parity and Zig-only claims separate | The docs already rely on that distinction to stay honest. |
| Make fixture cost part of tranche selection | Parser breadth only matters if the new language can be verified cleanly. |
| Choose a single-language C# tranche | It adds a high-value language with stable declaration nodes and low verification cost without forcing a riskier multi-language bundle. |
| Keep the C# claim Zig-only and parser-backed | The fixture and CLI evidence prove bounded definition extraction, not shared semantic parity with the C reference. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
