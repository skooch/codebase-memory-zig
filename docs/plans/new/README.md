# Remaining Backlog Order

Refresh date: 2026-04-18

The current target contract and the shared follow-on parity slices are complete.
Everything left in `docs/plans/new/` is optional follow-on work except the
currently active plans that have moved into `docs/plans/in-progress/`.

## Active Now

- [parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/parser-accuracy-and-graph-fidelity-improvements-plan.md)
  - Earlier correctness slice still exists in `docs/plans/in-progress/`.

## Ordering Principles

- Fix correctness and contract drift before broadening surface area.
- Harden runtime and client behavior before widening product claims.
- Ship packaging before broader installer-ecosystem expansion.
- Add parser-backed language breadth before LSP-assisted or higher-order graph
  expansion.

## Recommended Execution Order

1. [large-repo-reliability-and-crash-safety-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/large-repo-reliability-and-crash-safety-improvements-plan.md)
   - Third because scale failures, hangs, and corruption invalidate any broader
     adoption story.
2. [06-runtime-lifecycle-extras-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-plan.md)
   - Build on the existing runtime work once correctness and scale boundaries are
     clearer.
3. [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/windows-installer-and-client-integration-improvements-plan.md)
   - Normalize startup, path, and client behavior before claiming a wider
     install surface.
4. [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-plan.md)
   - Make operational knobs explicit before packaging or expanding agent-side
     automation.
5. [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/release-and-setup-packaging-plan.md)
   - Establish the release artifact and setup contract before broader installer
     matrix work.
6. [installer-ecosystem-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/installer-ecosystem-parity-plan.md)
   - Expand agent coverage only after shared packaging and client behavior are
     stable.
7. [09-operations-script-suite-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/09-operations-script-suite-plan.md)
   - Operational credibility belongs after the runtime, packaging, and install
     contracts stop moving.
8. [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md)
    - This is the first concrete parser-backed language-expansion tranche.
9. [08-hybrid-type-resolution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md)
    - Hybrid resolution is higher risk and should land only after the repo has a
      stronger parser-backed baseline and cleaner runtime semantics.
10. [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
    - Use this as the broader post-tranche language queue after Plan 07 proves
      the next parser-backed slice.
11. [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
    - Keep higher-order graph expansion last, after graph correctness,
      discovery/query semantics, scale, and language posture are stronger.

## Dependency Notes

- [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md) is the execution tranche.
  [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
  is the broader queue and should not start first.
- [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/windows-installer-and-client-integration-improvements-plan.md)
  should land before [installer-ecosystem-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/installer-ecosystem-parity-plan.md).
- [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/release-and-setup-packaging-plan.md)
  should land before [installer-ecosystem-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/installer-ecosystem-parity-plan.md).
- [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
  assumes the discovery/query, reliability, and language contracts are already
  firmer than they are today.

## Start Here

The next unopened plan remains
[large-repo-reliability-and-crash-safety-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/large-repo-reliability-and-crash-safety-improvements-plan.md).
