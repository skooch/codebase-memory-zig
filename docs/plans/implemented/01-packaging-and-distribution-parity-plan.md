# Plan: Packaging And Distribution Parity

## Goal
Close the biggest drop-in replacement credibility gap by giving the Zig port a release-oriented distribution story with packaged artifacts, setup entrypoints, and documented install flows instead of relying primarily on local source builds.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/ready-to-go/01-packaging-and-distribution-parity-plan.md`
- Create: `docs/plans/new/ready-to-go/01-packaging-and-distribution-parity-progress.md`
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
- [ ] Re-read the original release, setup, and packaging flows and capture the overlapping artifact and bootstrap expectations in `docs/gap-analysis.md`.
- [ ] Define the exact Zig release outputs, setup entrypoints, and verification commands in `docs/plans/new/ready-to-go/01-packaging-and-distribution-parity-progress.md`.
- [ ] Narrow the scope to shared packaging behavior only, keeping agent-specific config installation separate from this plan.
- **Status:** pending

### Phase 2: Implement Packaging And Setup Assets
- [ ] Extend `build.zig` so the repo can emit versioned distributable outputs suitable for release packaging rather than only local debug builds.
- [ ] Add `scripts/setup.sh`, `scripts/setup-windows.ps1`, and `scripts/package-release.sh` so local and CI setup flows can install or unpack the Zig binary consistently.
- [ ] Add `.github/workflows/release.yml` and `docs/install.md` so the repo documents and automates a reproducible binary-distribution story.
- **Status:** pending

### Phase 3: Verify And Reclassify
- [ ] Run `zig build`, `bash scripts/package-release.sh`, and the setup scripts on temp install prefixes until the packaging flow produces usable release artifacts and installs them successfully.
- [ ] Update `docs/port-comparison.md` so the packaging and setup rows move out of `Partial` only after the release artifacts and scripts are proven.
- [ ] Record the final verification transcript and any intentionally unsupported release variants in `docs/plans/new/ready-to-go/01-packaging-and-distribution-parity-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Keep packaging separate from agent setup | Packaging is the first thing users judge when evaluating a drop-in replacement, and it should not be blocked on agent-specific installer behavior. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
