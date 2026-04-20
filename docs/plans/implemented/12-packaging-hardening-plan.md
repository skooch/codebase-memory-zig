# Plan: Packaging Hardening

## Goal
Add release-hardening layers beyond the currently verified packaging flow so the docs can describe a stronger release posture without overstating what the repo automates.

## Current Phase
Complete

## File Map
- Create: `docs/plans/new/12-packaging-hardening-plan.md`
- Create: `docs/plans/new/12-packaging-hardening-progress.md`
- Modify: `docs/install.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `scripts/package-release.sh`
- Modify: `install.sh`
- Modify: `install.ps1`
- Modify: `.github/workflows/release.yml`
- Create: `docs/release-hardening.md`
- Modify: `docs/plans/new/README.md`

## Phases

### Phase 1: Choose the next hardening tranche
- [x] Break the remaining packaging debt into concrete slices such as checksum provenance, signing hooks, attestation metadata, archive verification, or installer trust signals.
- [x] Select the next hardening tranche that can be implemented and verified in-repo without pretending that off-repo signing infrastructure already exists.
- [x] Record the chosen release-hardening tranche and explicit exclusions in `docs/plans/in-progress/12-packaging-hardening-progress.md`.
- **Status:** complete

### Phase 2: Implement the selected release-hardening slice
- [x] Extend `scripts/package-release.sh` and the release workflow for the selected hardening tranche.
- [x] Update `install.sh` and `install.ps1` because the chosen hardening behavior changes installer-visible expectations.
- [x] Add the necessary maintainer documentation in `docs/release-hardening.md` and `docs/install.md`.
- **Status:** complete

### Phase 3: Rebaseline packaging claims
- [x] Re-run the packaging verification slice required by the selected hardening work.
- [x] Update `docs/port-comparison.md` and `docs/gap-analysis.md` so the packaging row reflects the new measured release posture.
- [x] Move the plan and progress files through `in-progress` to `implemented` only after the hardening slice is documented and verified.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep packaging hardening separate from installer behavior parity | Release hardening and installer semantics have different verification needs. |
| Choose only hardening steps that can be verified inside this repo | This avoids writing plans around missing signing infrastructure. |
| Add maintainer docs as part of the feature, not as a follow-up | Packaging claims are easy to lose without explicit operator guidance. |
| Choose a repo-owned release manifest slice instead of signing or attestation | The repo can generate, validate, and install against manifest metadata today without pretending that external trust infrastructure already exists. |
| Keep manifest verification additive instead of making it a hard requirement for older release directories | This preserves compatibility with previously packaged local directories while hardening new releases. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Fresh-worktree packaging failed because vendored grammar files were missing | Ran `scripts/package-release.sh` directly in the new worktree | Repaired the worktree with the documented bootstrap plus grammar fetch path, then re-ran packaging successfully |
| The draft-release workflow dropped one per-job manifest and then failed to discover the renamed files | Simulated the publish job locally on distinct macOS and Windows packaging outputs | Preserved unique manifest filenames during assembly and widened the merge-step glob to match them |
