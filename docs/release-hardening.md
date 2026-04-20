# Release Hardening

This document records the release-hardening slice that is implemented and
verified inside this repo today.

## Current hardening contract

- `scripts/package-release.sh` emits:
  - target archives
  - `checksums.txt`
  - `release-manifest.json`
- each manifest entry records:
  - target triple
  - normalized `os` and `arch`
  - archive filename
  - installed binary filename
  - archive type
  - SHA-256 digest
  - archive byte size
- the manifest also records:
  - `schema_version`
  - release `version`
  - source `git` commit used for packaging

## Installer behavior

- `install.sh` downloads the target archive plus `checksums.txt` and
  `release-manifest.json` when present
- the shell installer verifies the archive SHA-256 against:
  - `checksums.txt` when present
  - the matching manifest entry when present
- `install.ps1` applies the same rule on PowerShell hosts

The manifest is additive rather than a breaking release-format change. Older
release directories without a manifest still install through the checksum path.

## Release workflow behavior

`.github/workflows/release.yml` now treats the manifest as part of the release
contract:

- each packaging job uploads its own `release-manifest.json`
- the publish job merges those manifests
- the publish job validates that:
  - every archive in the assembled release directory has exactly one manifest
    entry
  - every manifest digest matches the real archive
  - every manifest size matches the real archive
  - `checksums.txt` matches the same archive set
  - all per-job manifests agree on `version` and `source_commit`
- the merged `release-manifest.json` is uploaded with the draft release assets

## Deliberate exclusions

This repo does not currently claim:

- artifact signing
- Sigstore or GitHub provenance attestation
- SBOM generation
- malware or reputation scanning
- off-repo key management

Those are separate future hardening layers. The current slice strengthens the
repo-owned release contract without pretending that external trust
infrastructure already exists.
