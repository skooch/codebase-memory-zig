# Progress

## Session: 2026-04-20

### Phase 1: Choose the next hardening tranche
- **Status:** complete
- Actions:
  - Created the packaging-hardening plan as backlog item `12`.
  - Scoped it to one concrete release-hardening tranche rather than a generic release-quality umbrella.
  - Chose the repo-owned release-manifest tranche: archive metadata emission,
    installer verification, and publish-time manifest merge or validation.
  - Explicitly deferred signing, provenance, SBOM generation, and other
    off-repo trust infrastructure.
- Files modified:
  - `docs/plans/in-progress/12-packaging-hardening-plan.md`
  - `docs/plans/in-progress/12-packaging-hardening-progress.md`

### Phase 2: Implement the manifest hardening tranche
- **Status:** complete
- Actions:
  - Extended `scripts/package-release.sh` to emit `release-manifest.json`
    alongside `checksums.txt`.
  - Updated `install.sh` and `install.ps1` to verify the target archive against
    the manifest when that file is present.
  - Updated `.github/workflows/release.yml` to merge per-job manifests and
    validate them against the assembled release directory before publishing.
  - Added `docs/release-hardening.md` and refreshed `docs/install.md`.
- Files modified:
  - `scripts/package-release.sh`
  - `install.sh`
  - `install.ps1`
  - `.github/workflows/release.yml`
  - `docs/install.md`
  - `docs/release-hardening.md`

### Phase 3: Rebaseline packaging claims
- **Status:** complete
- Actions:
  - Re-ran the local packaging slice and both installer entrypoints against a
    local packaged release directory.
  - Simulated the publish-job release assembly and merged-manifest validation on
    real packaged macOS and Windows artifacts.
  - Rebased the packaging row and gap-analysis language to the verified
    manifest-backed contract.
  - Prepared the plan for archival into `docs/plans/implemented/`.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`
  - `docs/plans/in-progress/12-packaging-hardening-plan.md`

### Verification
- `bash -n install.sh scripts/package-release.sh scripts/setup.sh`
- `zig build`
- `zig build test`
- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
- `bash scripts/fetch_grammars.sh --force`
- `bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-verify --target aarch64-macos --target x86_64-windows-gnu`
- `CBM_DOWNLOAD_URL="file://$(pwd)/dist/release-verify" bash install.sh --dir /tmp/cbm-install-verify --skip-config`
- `./.tools/pwsh/pwsh -NoLogo -NoProfile -File ./install.ps1 -BaseUrl "$(pwd)/dist/release-verify" -InstallDir /tmp/cbm-install-ps -SkipConfig`
- `bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-macos --target aarch64-macos`
- `bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-cross --target x86_64-windows-gnu`
- local simulation of the release-workflow assemble and merged-manifest validation step on the packaged outputs
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "workflow ok"'`

### Outcome
- local package verification produced:
  - `cbm-darwin-arm64.tar.gz`
  - `cbm-windows-amd64.zip`
  - `checksums.txt`
  - `release-manifest.json`
- both installers reported `Checksum verified.` and `Release manifest verified.`
- the publish-step simulation merged `2` artifacts into the final
  `release-manifest.json` and validated digests plus sizes against the assembled
  release directory

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-20 | `scripts/package-release.sh` failed in the worktree because vendored grammar files were missing | Tried the packaging run directly from the fresh worktree | Repaired the worktree with `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig` and `bash scripts/fetch_grammars.sh --force`, then re-ran the packaging verification successfully |
| 2026-04-20 | The release workflow copied both per-job manifests into `release/` under the same filename, and the merge glob missed the renamed form | Simulated the publish job locally after packaging distinct macOS and Windows outputs | Updated `.github/workflows/release.yml` to preserve unique manifest filenames and to glob `*release-manifest.json`, then re-ran the publish simulation successfully |
