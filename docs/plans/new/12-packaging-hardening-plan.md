# Plan: Packaging Hardening

## Goal
Add release-hardening layers beyond the currently verified packaging flow so the docs can describe a stronger release posture without overstating what the repo automates.

## Current Phase
Phase 1

## File Map
- Create: `docs/plans/new/12-packaging-hardening-plan.md`
- Create: `docs/plans/new/12-packaging-hardening-progress.md`
- Modify: `docs/install.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `build.zig`
- Modify: `scripts/package-release.sh`
- Modify: `install.sh`
- Modify: `install.ps1`
- Modify: `.github/workflows/release.yml`
- Create: `docs/release-hardening.md`

## Phases

### Phase 1: Choose the next hardening tranche
- [ ] Break the remaining packaging debt into concrete slices such as checksum provenance, signing hooks, attestation metadata, archive verification, or installer trust signals.
- [ ] Select the next hardening tranche that can be implemented and verified in-repo without pretending that off-repo signing infrastructure already exists.
- [ ] Record the chosen release-hardening tranche and explicit exclusions in `docs/plans/in-progress/12-packaging-hardening-progress.md`.
- **Status:** pending

### Phase 2: Implement the selected release-hardening slice
- [ ] Extend `build.zig`, `scripts/package-release.sh`, and the release workflow for the selected hardening tranche.
- [ ] Update `install.sh` and `install.ps1` only if the chosen hardening behavior changes installer-visible expectations.
- [ ] Add the necessary maintainer documentation in `docs/release-hardening.md` and `docs/install.md`.
- **Status:** pending

### Phase 3: Rebaseline packaging claims
- [ ] Re-run the packaging verification slice required by the selected hardening work.
- [ ] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the packaging row reflects the new measured release posture.
- [ ] Move the plan and progress files through `in-progress` to `implemented` only after the hardening slice is documented and verified.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep packaging hardening separate from installer behavior parity | Release hardening and installer semantics have different verification needs. |
| Choose only hardening steps that can be verified inside this repo | This avoids writing plans around missing signing infrastructure. |
| Add maintainer docs as part of the feature, not as a follow-up | Packaging claims are easy to lose without explicit operator guidance. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
