# Plan: Release And Setup Packaging Parity

## Goal
Recreate the original's release-oriented packaging and setup surface for the Zig port, including installable artifacts, setup scripts, and documented distribution flows.

## Current Phase
Implemented

## File Map
- Modify: `docs/plans/implemented/release-and-setup-packaging-plan.md`
- Create: `docs/plans/implemented/release-and-setup-packaging-progress.md`
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
- [x] Define the supported Zig release outputs, setup entrypoints, and verification commands in `docs/plans/implemented/release-and-setup-packaging-progress.md`.
- [x] Add the release file map for shell, PowerShell, and CI packaging entrypoints to this plan and keep the scope explicitly separate from agent-config behavior already covered elsewhere.
- **Status:** complete

### Phase 2: Implement Release And Setup Assets
- [x] Extend `build.zig` so the project can emit versioned distributable artifacts suitable for release packaging instead of only local source builds.
- [x] Add `install.sh`, `install.ps1`, `scripts/setup.sh`, `scripts/setup-windows.ps1`, and `scripts/package-release.sh` so local and CI setup flows can install or unpack the Zig binary consistently.
- [x] Add `.github/workflows/release.yml` and `docs/install.md` so the repo ships a reproducible release story instead of leaving distribution implicit.
- **Status:** complete

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `bash scripts/package-release.sh`, the shell setup/install scripts, and the PowerShell entrypoints on a temp prefix until release packaging and setup flows complete successfully.
- [x] Update `docs/port-comparison.md` so the packaging and setup rows move out of `Partial` only after the release artifacts and scripts are proven.
- [x] Record the final packaging verification transcript in `docs/plans/implemented/release-and-setup-packaging-progress.md`.
- **Status:** complete

## Decisions
| Decision | Rationale |
|----------|-----------|
| Separate release packaging from agent-installer expansion | Packaging concerns the binary-distribution story, while agent integration concerns post-install config behavior. |
| Keep the packaging target narrower than the original's UI and attestation surface | The Zig repo cut the UI product and should prove standard binary distribution first before adding signing or provenance extras. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
| Fresh packaging worktree was missing vendored grammars | `zig build` failed before packaging work started. | Ran `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig` before verification and recorded that requirement in the progress log. |
| New `zig build release` step initially linked a Debug-built dependency graph | The first release-step implementation reused the debug `cbm` module and `tree_sitter` dependency. | Split the build graph so the `release` step has its own ReleaseSafe module and dependency closure. |
| Windows release packaging exposed POSIX-only env and tty assumptions in product code | Cross-target `x86_64-windows-gnu` packaging failed in `src/cli.zig`, `src/main.zig`, `src/discover.zig`, and `src/runtime_lifecycle.zig`. | Replaced those code paths with allocator-backed env reads and file-handle TTY checks so Windows release builds complete. |
| Windows zip packaging initially wrote to a relative output path after `cd` into the staging directory | The zip step failed with `Could not create output file (dist/release-check/cbm-windows-amd64.zip)`. | Normalized `OUTPUT_DIR` to an absolute path before archive creation. |
