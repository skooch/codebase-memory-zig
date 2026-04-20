# Install `cbm`

This document records the measured release-oriented install contract for the Zig
port.

## Release artifacts

- macOS and Linux: `cbm-<os>-<arch>.tar.gz`
- Windows: `cbm-windows-amd64.zip`
- Shared checksum file: `checksums.txt`
- Shared release manifest: `release-manifest.json`

## Entry points

- one-line installers:
  - `install.sh`
  - `install.ps1`
- setup wrappers:
  - `scripts/setup.sh`
  - `scripts/setup-windows.ps1`
- local release packager:
  - `scripts/package-release.sh`

## Verification contract

- `scripts/package-release.sh` now emits both `checksums.txt` and a
  repo-owned `release-manifest.json` with archive metadata, SHA-256 digests,
  sizes, target triples, and the source commit used to produce the artifacts.
- `install.sh` and `install.ps1` verify the target archive checksum when
  `checksums.txt` is present and also verify the matching manifest entry when
  `release-manifest.json` is present.
- `.github/workflows/release.yml` merges the per-job manifests, validates the
  merged result against the actual release archives plus `checksums.txt`, and
  then uploads the validated release set as a draft GitHub release.

## Current local verification path

Build a local release archive:

```sh
bash scripts/package-release.sh --version 0.0.0-dev
```

Install from a release directory without touching agent config:

```sh
CBM_DOWNLOAD_URL="file://$(pwd)/dist/release" bash install.sh --dir /tmp/cbm-install --skip-config
```

Install from the same release directory through PowerShell:

```sh
pwsh -NoLogo -NoProfile -File ./install.ps1 -BaseUrl "$(pwd)/dist/release" -InstallDir /tmp/cbm-install-ps -SkipConfig
```

Build and install from the current checkout instead:

```sh
bash scripts/setup.sh --from-source --dir /tmp/cbm-install --skip-config
```

## Scope boundary

This packaging story is intentionally separate from the agent-installer surface.
The release scripts are responsible for getting the `cbm` binary onto disk and
verifying it runs. The existing `cbm install` command remains responsible for
post-install MCP and agent configuration behavior.

Deliberate exclusions in the current hardening slice:

- no signing or external attestation
- no SBOM or malware-scanning pipeline
- no UI-variant packaging
- no off-repo trust infrastructure
