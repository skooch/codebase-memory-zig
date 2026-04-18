# Install `cbm`

This document records the release-oriented install contract for the Zig port as
it is being built out.

## Planned release artifacts

- macOS and Linux: `cbm-<os>-<arch>.tar.gz`
- Windows: `cbm-windows-amd64.zip`
- Shared checksum file: `checksums.txt`

## Planned entrypoints

- one-line installers:
  - `install.sh`
  - `install.ps1`
- setup wrappers:
  - `scripts/setup.sh`
  - `scripts/setup-windows.ps1`
- local release packager:
  - `scripts/package-release.sh`

## Current local verification path

Build a local release archive:

```sh
bash scripts/package-release.sh --version 0.0.0-dev
```

Install from a release directory without touching agent config:

```sh
CBM_DOWNLOAD_URL="file://$(pwd)/dist/release" bash install.sh --dir /tmp/cbm-install --skip-config
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
