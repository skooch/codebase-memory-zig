# Plan: Language Support Expansion Feature Cluster

## Goal
Choose and sequence new language and ecosystem support based on the upstream demand pattern, without repeating the original project’s tendency to advertise coverage before parser-backed fidelity exists.

## Research Basis

Upstream feature requests and pressure signals captured in this plan:
- Explicit language requests: `#35` (PowerShell), `#38` (CFML), `#39` (Luau), `#42` (QML), `#186` (GDScript)
- Evidence that “supported” can still mean shallow extraction if onboarding is rushed: `#236`

Upstream PRs that show both landed and attempted expansion paths:
- Landed language additions: `#2` (C#), `#3` (Kotlin), `#4` (Ruby)
- Landed ecosystem/resource additions: `#87` (Kubernetes and Kustomize), `#122` (DeviceTree and VHDL)
- Enablers for controlled expansion: `#60`, `#73` (extension-to-language mappings)
- Large unmerged expansion bundle showing scope risk: `#162`

Observed upstream pattern:
- New-language work succeeded when it shipped with grammar wiring, language-spec registration, and regression tests in one slice.
- Expansion got riskier when it combined many semantic ambitions at once or when it stretched beyond the current verification harness.

## Current Phase
Completed

## File Map
- Modify: `docs/plans/implemented/language-support-expansion-feature-cluster-plan.md`
- Create: `docs/plans/implemented/language-support-expansion-feature-cluster-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `build.zig`
- Modify: `scripts/fetch_grammars.sh`
- Modify: `src/discover.zig`
- Modify: `src/extractor.zig`
- Modify: `src/store_test.zig`
- Create: `docs/language-support.md`
- Create: `testdata/interop/language-expansion/powershell-basic/main.ps1`
- Create: `testdata/interop/language-expansion/gdscript-basic/main.gd`

## Phases

### Phase 1: Rank the Expansion Queue
- [x] Convert the upstream language requests into a scored queue in `docs/gap-analysis.md` using demand, parser availability, overlap with current Zig goals, and expected verification cost.
- [x] Add placeholder fixtures for the first candidate tranche under `testdata/interop/language-expansion/` so grammar onboarding is planned against exact examples from day one.
- [x] Record the chosen tranche, rejected tranche, and verification commands in `docs/plans/implemented/language-support-expansion-feature-cluster-progress.md`.
- **Status:** completed

### Phase 2: Build a Safe Onboarding Path
- [x] Extend `build.zig`, `scripts/fetch_grammars.sh`, `src/discover.zig`, `src/extractor.zig`, and `src/pipeline.zig` so the chosen PowerShell and GDScript tranche has explicit grammar wiring, deterministic selection, and parser-backed definition coverage before any broader parity claim is made.
- [x] Add `docs/language-support.md` to document the difference between extension detection, parser-backed extraction, and higher-level semantic parity.
- [x] Preserve QML and the remaining unsupported or lower-priority requests as documented deferred lanes instead of pseudo-support through heuristics alone.
- **Status:** completed

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and fixture-level graph queries for the chosen tranche until definition extraction and basic search behavior are stable.
- [x] Update `docs/port-comparison.md` and `docs/gap-analysis.md` only for the languages whose parser-backed contract is now verified.
- [x] Record the next candidate tranche and rejected requests in `docs/plans/implemented/language-support-expansion-feature-cluster-progress.md`.
- **Status:** completed

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat “extension recognized” and “language supported” as different claims | The upstream issue history shows that users experience shallow extraction as a broken promise, not partial success. |
| Favor small, verified tranches over broad headline counts | The upstream project benefited from incremental language landings that included tests and docs. |
| Start with PowerShell and GDScript, defer QML | PowerShell and GDScript both have maintained grammars with low-cost declaration coverage, while QML’s first useful slice is already object-model-heavy and not a good fit for the same bounded onboarding pass. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| `scripts/fetch_grammars.sh` failed immediately on `declare -A` under `set -u` | Ran the updated script on the host’s system Bash | Replaced associative arrays with portable `case` helpers and documented the Bash 3.2 constraint in `CLAUDE.md`. |
