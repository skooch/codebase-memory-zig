# Operations

This repo ships a small reproducible operations surface for maintainers and
evaluators. It is intentionally narrower than the original C repo's full
release, fuzzing, and binary-audit stack.

## Benchmarking

Full compare mode uses both the Zig binary and the sibling C reference repo:

```sh
bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json
```

Zig-only mode is the CI-safe path and does not require the sibling C repo:

```sh
bash scripts/run_benchmark_suite.sh --zig-only --manifest testdata/bench/stress-manifest.json
```

Useful flags:

```sh
bash scripts/run_benchmark_suite.sh --zig-only --repo-id self-repo
bash scripts/run_benchmark_suite.sh --report-dir .benchmark_reports/ops
```

Outputs:

- `.benchmark_reports/benchmark_report.json`
- `.benchmark_reports/benchmark_report.md`

## Soak

The soak runner creates a temporary local repo, mutates it across repeated
iterations, reindexes it, and runs a couple of representative queries each
cycle.

```sh
bash scripts/run_soak_suite.sh
bash scripts/run_soak_suite.sh --iterations 8 --report-dir .soak_reports/manual
```

Outputs:

- `.soak_reports/soak_report.json`
- `.soak_reports/soak_report.md`

## Security Audit

The static audit focuses on checks this Zig repo can enforce portably today:

- shell syntax checks for repo-owned shell entrypoints
- rejection of download-and-exec shell patterns in scripts and workflows
- rejection of insecure `http://` runtime URLs in core source and install paths
- allowlist enforcement for runtime HTTP client usage
- allowlist enforcement for `rm -rf` usage staying scoped to temp/work dirs

Run it with:

```sh
bash scripts/run_security_audit.sh
```

Outputs:

- `.security_reports/security_audit_report.json`
- `.security_reports/security_audit_report.md`
