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
