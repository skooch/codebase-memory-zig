# Release And Setup Packaging Progress

## Scope

This plan adds a reproducible release and setup story to the Zig port so the
repo can ship installable artifacts instead of relying only on source builds.

Current focus:
- versioned release archives for the standard `cbm` binary
- repo-owned shell and PowerShell install/setup entrypoints
- local packaging automation that CI can reuse
- documentation that separates binary distribution from post-install agent
  configuration behavior

## Phase 1 Contract

### Upstream packaging surface to overlap

From `/Users/skooch/projects/codebase-memory-mcp`:

- release workflow
  - `.github/workflows/release.yml`
  - release job shape is broader than the Zig target:
    - lint
    - test
    - build
    - smoke
    - optional soak
    - draft release
    - verify
    - publish
- install entrypoints
  - `install.sh`
  - `install.ps1`
  - both download release archives, verify checksums, extract the binary,
    verify `--version`, and optionally run `install -y`
- setup/bootstrap entrypoints
  - `scripts/setup.sh`
  - `scripts/setup-windows.ps1`
  - these are broader convenience scripts that can either download a release
    artifact or build from source
- artifact expectations documented in `README.md`
  - macOS and Linux use `.tar.gz`
  - Windows uses `.zip`
  - every release includes `checksums.txt`
  - original also ships a UI variant, which is intentionally out of scope for
    the Zig repo

### Supported Zig packaging target for this plan

- release artifacts
  - `cbm-<os>-<arch>.tar.gz` for macOS and Linux
  - `cbm-windows-amd64.zip` for Windows
  - `checksums.txt` for release verification
- install/setup entrypoints
  - `install.sh`
  - `install.ps1`
  - `scripts/setup.sh`
  - `scripts/setup-windows.ps1`
  - `scripts/package-release.sh`
- CI/release entrypoint
  - `.github/workflows/release.yml`
- user-facing install documentation
  - `docs/install.md`

### Explicit non-goals for this plan

- no UI variant packaging
- no release signing, SBOM, provenance attestation, or VirusTotal gate in the
  first slice
- no expansion of agent-matrix behavior beyond what the Zig CLI already ships

### Expected verification commands

```sh
zig build
bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-check --target aarch64-macos --target x86_64-windows-gnu
bash install.sh --dir /tmp/cbm-install --skip-config
bash scripts/setup.sh --dir /tmp/cbm-setup --skip-config
pwsh -File install.ps1 -InstallDir /tmp/cbm-ps-install -SkipConfig
pwsh -File scripts/setup-windows.ps1 -InstallDir /tmp/cbm-win-setup -SkipConfig
pwsh -File scripts/setup-windows.ps1 -FromSource -InstallDir /tmp/cbm-ps-source -SkipConfig
```

These are the final end-state contract checks for this plan.

## Phase 1 Checkpoint: Packaging Contract

Packaging baseline locked on 2026-04-19:

- moved the packaging plan into `docs/plans/in-progress/`
- corrected the file map so it matches the upstream distribution surface:
  install entrypoints, setup entrypoints, packaging script, release workflow,
  and install docs
- constrained the Zig overlap to the standard binary packaging story:
  archive outputs, checksums, setup/install scripts, and release automation
- kept UI artifacts, signing, attestation, and broader agent-installer behavior
  out of scope for this plan

Verification for this slice:

```sh
git status --short --branch
sed -n '1,260p' /Users/skooch/projects/codebase-memory-mcp/.github/workflows/release.yml
sed -n '1,260p' /Users/skooch/projects/codebase-memory-mcp/install.sh
sed -n '1,260p' /Users/skooch/projects/codebase-memory-mcp/install.ps1
sed -n '1,260p' /Users/skooch/projects/codebase-memory-mcp/scripts/setup.sh
sed -n '1,260p' /Users/skooch/projects/codebase-memory-mcp/scripts/setup-windows.ps1
```

Results:

- active worktree confirmed at
  `/Users/skooch/projects/worktrees/release-setup-packaging`
  on `codex/release-setup-packaging`
- upstream packaging surface captured and narrowed into a concrete Zig target
  before any build or script implementation changes

## Phase 2 Checkpoint: Host Packaging And Unix Setup

First packaging implementation slice on 2026-04-19:

- added `scripts/package-release.sh`
  - builds ReleaseSafe host or explicit-target archives
  - emits release-style archive names plus `checksums.txt`
  - includes the shell installer in Unix archives when present
- added `install.sh`
  - downloads a packaged release archive
  - verifies checksums when available
  - installs `cbm` into a chosen directory
  - optionally runs `cbm install -y`
- added `scripts/setup.sh`
  - defaults to the packaged-release install path via `install.sh`
  - supports `--from-source` to build and install the current checkout with
    Zig instead of downloading a release archive
- added `docs/install.md`
  - records the current local packaging and install contract

Verification for this slice:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
bash -n install.sh scripts/setup.sh scripts/package-release.sh
zig build
bash scripts/package-release.sh --version 0.0.0-dev
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release" bash install.sh --dir /tmp/cbm-install --skip-config
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release" bash scripts/setup.sh --dir /tmp/cbm-setup --skip-config
bash scripts/setup.sh --from-source --dir /tmp/cbm-source --skip-config
command -v pwsh || true
```

Results:

- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
  completed because this fresh worktree was missing vendored grammars
- shell syntax checks passed
- `zig build` passed
- `bash scripts/package-release.sh --version 0.0.0-dev` produced:
  - `dist/release/cbm-darwin-arm64.tar.gz`
  - `dist/release/checksums.txt`
- `bash install.sh --dir /tmp/cbm-install --skip-config` passed against the
  local file-backed release directory
- `bash scripts/setup.sh --dir /tmp/cbm-setup --skip-config` passed against
  the same local release directory
- `bash scripts/setup.sh --from-source --dir /tmp/cbm-source --skip-config`
  passed against the current checkout
- `pwsh` was not initially available in this environment

Remaining Phase 2 scope after this checkpoint:

- add the PowerShell install and setup entrypoints:
  - `install.ps1`
  - `scripts/setup-windows.ps1`
- add CI-oriented release automation in `.github/workflows/release.yml`
- decide whether `build.zig` needs a dedicated release step beyond the current
  `zig build --prefix` contract that `scripts/package-release.sh` already uses

## Phase 2 Checkpoint: Cross-Platform Packaging Surface

Second packaging implementation slice on 2026-04-19:

- `build.zig`
  - now exposes a dedicated `zig build release` step for a ReleaseSafe install
    of `cbm`
  - keeps the release dependency graph separate from the default debug build
- `install.ps1`
  - now installs the host platform release archive from a release directory or
    URL, verifies checksums, and optionally runs `cbm install -y`
- `scripts/setup-windows.ps1`
  - now supports both packaged-release install and `-FromSource` builds
  - is PowerShell Core compatible, so it can be verified on a non-Windows host
    while still packaging Windows artifacts
- `.github/workflows/release.yml`
  - now packages macOS on `macos-latest`
  - packages Linux and Windows on `ubuntu-latest`
  - assembles those archives into a draft GitHub release
- product portability fixes landed under the packaging plan:
  - allocator-backed env reads for Windows-target build safety in:
    - `src/cli.zig`
    - `src/discover.zig`
    - `src/main.zig`
    - `src/runtime_lifecycle.zig`
  - file-handle TTY detection in `src/main.zig`
  - absolute output handling in `scripts/package-release.sh`

Verification for this slice:

```sh
zig build
zig build release
bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-check --target aarch64-macos --target x86_64-windows-gnu
tar -tzf dist/release-check/cbm-darwin-arm64.tar.gz | sort
unzip -l dist/release-check/cbm-windows-amd64.zip
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check" bash install.sh --dir /tmp/cbm-install --skip-config
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check" bash scripts/setup.sh --dir /tmp/cbm-setup --skip-config
gh release download v7.5.4 -R PowerShell/PowerShell -p 'powershell-7.5.4-osx-arm64.tar.gz' -D /tmp/pwsh-gh.LdvXSs
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File install.ps1 -InstallDir /tmp/cbm-ps-install -SkipConfig -BaseUrl file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File scripts/setup-windows.ps1 -InstallDir /tmp/cbm-ps-setup -SkipConfig -BaseUrl file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File scripts/setup-windows.ps1 -FromSource -InstallDir /tmp/cbm-ps-source -SkipConfig
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "ok"'
```

Results:

- `zig build` passed
- `zig build release` passed
- `bash scripts/package-release.sh ... --target aarch64-macos --target x86_64-windows-gnu` passed and produced:
  - `dist/release-check/cbm-darwin-arm64.tar.gz`
  - `dist/release-check/cbm-windows-amd64.zip`
  - `dist/release-check/checksums.txt`
- the Unix archive contains:
  - `cbm`
  - `install.sh`
- the Windows archive contains:
  - `cbm.exe`
  - `install.ps1`
- packaged shell install and setup entrypoints passed against the local
  file-backed release directory
- packaged PowerShell install and setup entrypoints passed against the same
  local release directory using portable `pwsh 7.5.4`
- `scripts/setup-windows.ps1 -FromSource` passed through the new
  `zig build release` path
- `.github/workflows/release.yml` parsed successfully as YAML

## Phase 3 Completion

Plan closeout on 2026-04-19:

- the Zig repo now ships a reproducible standard-binary release story:
  - release archives
  - checksums
  - shell and PowerShell install/setup entrypoints
  - a repo-owned release workflow
  - install documentation
- the verified overlap remains intentionally narrower than the original's
  broader release pipeline:
  - no UI variant packaging
  - no signing, SBOM, provenance, or VirusTotal stages in this slice

Final verification set:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
bash -n install.sh scripts/setup.sh scripts/package-release.sh
zig build
zig build release
bash scripts/package-release.sh --version 0.0.0-dev --output-dir dist/release-check --target aarch64-macos --target x86_64-windows-gnu
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check" bash install.sh --dir /tmp/cbm-install --skip-config
CBM_DOWNLOAD_URL="file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check" bash scripts/setup.sh --dir /tmp/cbm-setup --skip-config
bash scripts/setup.sh --from-source --dir /tmp/cbm-source --skip-config
gh release download v7.5.4 -R PowerShell/PowerShell -p 'powershell-7.5.4-osx-arm64.tar.gz' -D /tmp/pwsh-gh.LdvXSs
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File install.ps1 -InstallDir /tmp/cbm-ps-install -SkipConfig -BaseUrl file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File scripts/setup-windows.ps1 -InstallDir /tmp/cbm-ps-setup -SkipConfig -BaseUrl file:///Users/skooch/projects/worktrees/release-setup-packaging/dist/release-check
"/tmp/pwsh-gh.LdvXSs/pwsh" -NoLogo -NoProfile -File scripts/setup-windows.ps1 -FromSource -InstallDir /tmp/cbm-ps-source -SkipConfig
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "ok"'
```

Final results:

- all shell-side packaging and setup checks passed
- all PowerShell entrypoint checks passed with portable `pwsh 7.5.4`
- the Windows release artifact now builds successfully via the local packager
- the release workflow file parses successfully
