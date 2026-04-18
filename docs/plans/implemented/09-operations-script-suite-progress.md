# Operations Script Suite Progress

## Scope

This plan restores a credible repo-owned operations surface around benchmarks,
soak checks, and static security or audit checks without trying to clone the
original repository's entire release and security pipeline.

Current focus:
- keep the existing benchmark suite as the anchor and make it easier to run in
  CI or local worktrees
- add one reproducible soak entrypoint for repeated MCP and indexing workload
  cycles
- add one repo-owned static audit entrypoint for risky shell, network, and
  installer patterns in the Zig repo
- wire those scripts into a single CI workflow and maintainer docs

## Phase 1 Contract

### Original operational surface reviewed

- benchmarking
  - `scripts/benchmark-index.sh`
  - `scripts/clone-bench-repos.sh`
- soak / endurance
  - `scripts/soak-test.sh`
  - reusable soak workflows in `.github/workflows/_soak.yml`
- static and post-build security layers
  - `scripts/security-audit.sh`
  - `scripts/security-strings.sh`
  - `scripts/security-install.sh`
  - `scripts/security-network.sh`
  - `scripts/security-fuzz.sh`
  - `scripts/security-fuzz-random.sh`
  - `scripts/security-vendored.sh`
- umbrella CI wiring
  - `_lint.yml`
  - `_smoke.yml`
  - `_soak.yml`

### Bounded overlap to implement here

- keep the existing repo-owned benchmark harness and expose a stable wrapper
  contract around it
- add a soak script that:
  - runs against the Zig binary only
  - uses a local generated or fixture-backed project
  - performs repeated index and query cycles
  - emits a machine-readable summary under a repo-owned output directory
- add a static security or audit script that:
  - works on this Zig repo today
  - does not depend on unavailable platform tools like `strace`
  - focuses on source and script checks this repo can enforce reliably
- add one CI workflow that runs the benchmark, soak, and audit entrypoints on
  GitHub Actions

### Explicit non-goals for this plan

- reproducing the original's full multi-layer binary audit and fuzzing stack
- reproducing nightly or multi-hour soak coverage
- folding release publication or packaging checks into this operations plan
- adding external hosted benchmark repos as mandatory CI inputs

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json
bash scripts/run_soak_suite.sh
bash scripts/run_security_audit.sh
```

## Phase 1 Checkpoint: Contract Lock

Plan-start pass on 2026-04-19:

- reviewed the original repo's benchmark, soak, and security script surface
- confirmed the Zig repo already has a working benchmark wrapper plus Python
  harness and stress manifest
- narrowed the plan to one benchmark wrapper, one soak entrypoint, one static
  audit entrypoint, maintainer docs, and one CI workflow
- excluded the original's fuzzing, UI-specific, network-trace, and binary
  string audits from the required overlap because this repo cannot reproduce
  those layers portably in the current environment

Verification for this slice:

```sh
git status --short --branch
```

Results:

- worktree confirmed at
  `/Users/skooch/projects/worktrees/operations-script-suite`
  on `codex/operations-script-suite`
- plan state corrected from `new/ready-to-go` to `in-progress` before
  implementation

## Phase 2 Checkpoint: Scripts, Docs, and CI

Implementation completed on 2026-04-19:

- benchmark wrapper:
  - `scripts/run_benchmark_suite.sh` now accepts `--zig-only`, `--manifest`,
    `--report-dir`, and benchmark passthrough flags without requiring the
    sibling C binary in CI-safe mode
  - `scripts/run_benchmark_suite.py` now supports Zig-only reporting and keeps
    Python 3.9 compatibility for the embedded harness
- soak suite:
  - `scripts/run_soak_suite.sh` now generates a local temporary git repo and
    runs repeated `index_repository`, `search_graph`, and `get_architecture`
    cycles against the Zig binary
  - the soak wrapper emits JSON and Markdown reports under `.soak_reports/`
- static audit suite:
  - `scripts/run_security_audit.sh` now performs portable shell, URL,
    installer-pattern, and destructive-command checks on this repo
  - the audit wrapper emits JSON and Markdown reports under
    `.security_reports/`
- maintainer and CI wiring:
  - `docs/operations.md` documents the supported benchmark, soak, and audit
    entrypoints
  - `.github/workflows/ops-checks.yml` runs benchmark, soak, and static audit
    coverage on GitHub Actions and uploads the generated reports

Verification for this slice:

```sh
bash -n scripts/run_benchmark_suite.sh scripts/run_soak_suite.sh scripts/run_security_audit.sh
python3 -m py_compile scripts/run_benchmark_suite.py
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ops-checks.yml"); puts "ok"'
```

Results:

- shell syntax checks passed
- the Python harness compiles cleanly under the system `python3`
- the GitHub Actions workflow YAML parses cleanly

## Phase 3 Checkpoint: Verification and Reclassification

Full verification completed on 2026-04-19:

```sh
zig build
zig build test
bash scripts/run_benchmark_suite.sh --zig-only --manifest testdata/bench/stress-manifest.json --report-dir .benchmark_reports/ops
bash scripts/run_soak_suite.sh --iterations 4 --report-dir .soak_reports/ops
bash scripts/run_security_audit.sh .security_reports/ops
```

Results:

- `zig build` passed
- `zig build test` passed
- benchmark report:
  - `self-repo` Zig cold-index median: `1340.308 ms`
  - `sqlite-amalgamation` Zig cold-index median: `72.769 ms`
- soak report:
  - index median: `55.428 ms`
  - index p95: `303.966 ms`
  - `search_graph` median: `11.075 ms`
  - `get_architecture` median: `11.684 ms`
- security audit report:
  - check count: `17`
  - failure count: `0`
- `docs/port-comparison.md` now classifies the operations-script rows as
  `Near parity` instead of `Partial` or `Deferred`

Intentional residual delta after completion:

- no binary-string audit layer equivalent to the original's post-build checks
- no runtime network-trace audit layer
- no fuzz harnesses in the Zig repo today
- no nightly or multi-hour soak tier beyond the reproducible local suite
