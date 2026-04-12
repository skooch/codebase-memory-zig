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
Phase 1

## File Map
- Modify: `docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md`
- Create: `docs/plans/new/improvements/language-support-expansion-feature-cluster-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `build.zig`
- Modify: `build.zig.zon`
- Modify: `src/discover.zig`
- Modify: `src/extractor.zig`
- Modify: `src/pipeline.zig`
- Create: `docs/language-support.md`
- Create: `testdata/interop/language-expansion/powershell-basic/main.ps1`
- Create: `testdata/interop/language-expansion/gdscript-basic/main.gd`
- Create: `testdata/interop/language-expansion/qml-basic/Main.qml`

## Phases

### Phase 1: Rank the Expansion Queue
- [ ] Convert the upstream language requests into a scored queue in `docs/gap-analysis.md` using demand, parser availability, overlap with current Zig goals, and expected verification cost.
- [ ] Add placeholder fixtures for the first candidate tranche under `testdata/interop/language-expansion/` so grammar onboarding is planned against exact examples from day one.
- [ ] Record the chosen tranche, rejected tranche, and verification commands in `docs/plans/new/improvements/language-support-expansion-feature-cluster-progress.md`.
- **Status:** pending

### Phase 2: Build a Safe Onboarding Path
- [ ] Extend `build.zig`, `build.zig.zon`, `src/discover.zig`, `src/extractor.zig`, and `src/pipeline.zig` so the next language tranche has explicit grammar wiring, deterministic selection, and parser-backed definition coverage before any broader parity claim is made.
- [ ] Add `docs/language-support.md` to document the difference between extension detection, parser-backed extraction, and higher-level semantic parity.
- [ ] Preserve unsupported or low-priority requests as documented deferred lanes instead of pseudo-support through heuristics alone.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and fixture-level graph queries for the chosen tranche until definition extraction and basic search behavior are stable.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` only for the languages whose parser-backed contract is now verified.
- [ ] Record the next candidate tranche and any rejected requests in `docs/plans/new/improvements/language-support-expansion-feature-cluster-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Treat “extension recognized” and “language supported” as different claims | The upstream issue history shows that users experience shallow extraction as a broken promise, not partial success. |
| Favor small, verified tranches over broad headline counts | The upstream project benefited from incremental language landings that included tests and docs. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
