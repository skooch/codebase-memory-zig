# Plan: Release And Setup Packaging Parity

## Goal
Recreate the original's release-oriented packaging and setup surface for the Zig port, including installable artifacts, setup scripts, and documented distribution flows.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/release-and-setup-packaging-plan.md`
- Create: `docs/plans/new/release-and-setup-packaging-progress.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/gap-analysis.md`
- Modify: `build.zig`
- Create: `scripts/setup.sh`
- Create: `scripts/setup-windows.ps1`
- Create: `scripts/package-release.sh`
- Create: `.github/workflows/release.yml`
- Create: `docs/install.md`

## Phases

### Phase 1: Lock the Packaging Contract
- [ ] Re-read the original packaging and setup flows and capture the overlapping artifact, bootstrap, and release expectations in `docs/gap-analysis.md`.
- [ ] Define the supported Zig release outputs, setup entrypoints, and verification commands in `docs/plans/new/release-and-setup-packaging-progress.md`.
- [ ] Add the release file map for shell, PowerShell, and CI packaging entrypoints to this plan and keep the scope explicitly separate from agent-config behavior already covered elsewhere.
- **Status:** pending

### Phase 2: Implement Release And Setup Assets
- [ ] Extend `build.zig` so the project can emit versioned distributable artifacts suitable for release packaging instead of only local source builds.
- [ ] Add `scripts/setup.sh`, `scripts/setup-windows.ps1`, and `scripts/package-release.sh` so local and CI setup flows can install or unpack the Zig binary consistently.
- [ ] Add `.github/workflows/release.yml` and `docs/install.md` so the repo ships a reproducible release story instead of leaving distribution implicit.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `bash scripts/package-release.sh`, and the setup scripts on a temp prefix until release packaging and setup flows complete successfully.
- [ ] Update `docs/port-comparison.md` so the packaging and setup rows move out of `Partial` only after the release artifacts and scripts are proven.
- [ ] Record the final packaging verification transcript in `docs/plans/new/release-and-setup-packaging-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate release packaging from agent-installer expansion | Packaging concerns the binary-distribution story, while agent integration concerns post-install config behavior. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
