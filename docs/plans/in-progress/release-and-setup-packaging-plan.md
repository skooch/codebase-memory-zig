# Plan: Release And Setup Packaging Parity

## Goal
Recreate the original's release-oriented packaging and setup surface for the Zig port, including installable artifacts, setup scripts, and documented distribution flows.

## Current Phase
Phase 2

## File Map
- Modify: `docs/plans/in-progress/release-and-setup-packaging-plan.md`
- Create: `docs/plans/in-progress/release-and-setup-packaging-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/plans/new/README.md`
- Modify: `build.zig`
- Create: `install.sh`
- Create: `install.ps1`
- Create: `scripts/setup.sh`
- Create: `scripts/setup-windows.ps1`
- Create: `scripts/package-release.sh`
- Create: `.github/workflows/release.yml`
- Create: `docs/install.md`

## Phases

### Phase 1: Lock the Packaging Contract
- [x] Re-read the original packaging and setup flows and capture the overlapping artifact, bootstrap, and release expectations in `docs/gap-analysis.md`.
- [x] Define the supported Zig release outputs, setup entrypoints, and verification commands in `docs/plans/in-progress/release-and-setup-packaging-progress.md`.
- [x] Add the release file map for shell, PowerShell, and CI packaging entrypoints to this plan and keep the scope explicitly separate from agent-config behavior already covered elsewhere.
- **Status:** complete

### Phase 2: Implement Release And Setup Assets
- [ ] Extend `build.zig` so the project can emit versioned distributable artifacts suitable for release packaging instead of only local source builds.
- [ ] Add `install.sh`, `install.ps1`, `scripts/setup.sh`, `scripts/setup-windows.ps1`, and `scripts/package-release.sh` so local and CI setup flows can install or unpack the Zig binary consistently.
- [ ] Add `.github/workflows/release.yml` and `docs/install.md` so the repo ships a reproducible release story instead of leaving distribution implicit.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `bash scripts/package-release.sh`, the shell setup/install scripts, and the PowerShell entrypoints on a temp prefix until release packaging and setup flows complete successfully.
- [ ] Update `docs/port-comparison.md` so the packaging and setup rows move out of `Partial` only after the release artifacts and scripts are proven.
- [ ] Record the final packaging verification transcript in `docs/plans/in-progress/release-and-setup-packaging-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate release packaging from agent-installer expansion | Packaging concerns the binary-distribution story, while agent integration concerns post-install config behavior. |
| Keep the packaging target narrower than the original's UI and attestation surface | The Zig repo cut the UI product and should prove standard binary distribution first before adding signing or provenance extras. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
