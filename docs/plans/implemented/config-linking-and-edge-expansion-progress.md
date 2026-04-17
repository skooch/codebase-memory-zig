# Progress: Config Linking And Edge Expansion Follow-On

## 2026-04-16
- Resumed the old config-linking and edge-expansion plan from paused/superseded
  into
  `docs/plans/implemented/config-linking-and-edge-expansion-plan.md`.
- Re-scoped the plan around remaining optional work after graph-model parity:
  broader config key/language shapes and long-tail edge families only where the
  C reference exposes matching public fixture rows.
- Queued this plan behind the route graph follow-on.

## 2026-04-17
- The route graph follow-on reached full verification and moved to
  `docs/plans/implemented/route-graph-parity-plan.md`.
- This plan is now the active graph-enrichment child plan.
- Probed env-style config-key candidates before adding any new strict
  assertions:
  - Go probe: `config.toml` + `main.go` using `os.Getenv("DATABASE_URL")`
  - Python probe: `config.toml` + `main.py` using `os.getenv("DATABASE_URL")`
- Findings:
  - The Go probe showed a real public-overlap row in the C reference
    (`loadDatabaseUrl -> DATABASE_URL` over `CONFIGURES`), but Zig still missed
    it because env-style uppercase keys were normalized poorly and Go extraction
    remains a weaker substrate here. This probe stays unpromoted.
  - The Python probe produced a clean shared row on both implementations:
    `load_database_url -> DATABASE_URL` over `CONFIGURES`.
- Implemented the narrow fix in `src/pipeline.zig`:
  - env-style uppercase config keys like `DATABASE_URL` now normalize to
    `database url` instead of fragmenting into one-letter tokens
  - added focused regression coverage for the env-style normalization path and
    the new shared Python env-var config link case
- Promoted the accepted candidate into the repo as
  `testdata/interop/config-expansion/env_var_python/` with manifest id
  `config-expansion-env-var-python`.
- Verified the promoted fixture with:
  - `zig fmt src/pipeline.zig`
  - `zig build test`
  - `zig build`
  - `bash scripts/run_interop_alignment.sh --update-golden /tmp/config-expansion-env-var-python-manifest-Cl4otU.json`
  - `bash scripts/run_interop_alignment.sh --zig-only /tmp/config-expansion-env-var-python-manifest-Cl4otU.json`
  - `bash scripts/run_interop_alignment.sh /tmp/config-expansion-env-var-python-manifest-Cl4otU.json`
  - `bash scripts/run_interop_alignment.sh --zig-only`
  - `bash scripts/run_interop_alignment.sh`
- Result:
  - full Zig-only interop harness passed `24/24` fixtures
  - full C-vs-Zig alignment still reports only the 8 known non-config
    mismatches
  - no new config-related mismatches were introduced
  - `WRITES` / `READS` still do not have a proven shared public fixture row and
    remain documented future work instead of parity claims
- Concluded the config / edge follow-on is complete.

## Verification
- Probe reports inspected:
  - `/tmp/cbm-config-probe-rnpOxE/report/interop_alignment_report.json`
  - `/tmp/cbm-config-probe-py-NnHESX/report/interop_alignment_report.json`
- Repo reports inspected:
  - `/Users/skooch/projects/codebase-memory-zig/.interop_reports/interop_golden_report.json`
  - `/Users/skooch/projects/codebase-memory-zig/.interop_reports/interop_alignment_report.json`
