# Remaining Backlog Order

Refresh date: 2026-04-18

The current target contract and the shared follow-on parity slices are complete.
Everything left in `docs/plans/new/` is optional follow-on work except the
currently active parser-accuracy slice, which has moved into
`docs/plans/in-progress/`.

## Active Now

- [parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/parser-accuracy-and-graph-fidelity-improvements-plan.md)
  - Active in `/Users/skooch/projects/worktrees/parser-accuracy-fidelity` on
    `codex/parser-accuracy-fidelity`.

## Ordering Principles

- Fix correctness and contract drift before broadening surface area.
- Harden runtime and client behavior before widening product claims.
- Ship packaging before broader installer-ecosystem expansion.
- Add parser-backed language breadth before LSP-assisted or higher-order graph
  expansion.

## Recommended Execution Order

1. [discovery-indexing-scope-and-query-semantics-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/discovery-indexing-scope-and-query-semantics-improvements-plan.md)
   - Next because search and schema behavior need deterministic indexed scope
     before more data or more clients are added.
2. [large-repo-reliability-and-crash-safety-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/large-repo-reliability-and-crash-safety-improvements-plan.md)
   - Third because scale failures, hangs, and corruption invalidate any broader
     adoption story.
3. [06-runtime-lifecycle-extras-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-plan.md)
   - Build on the existing runtime work once correctness and scale boundaries are
     clearer.
4. [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/windows-installer-and-client-integration-improvements-plan.md)
   - Normalize startup, path, and client behavior before claiming a wider
     install surface.
5. [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-plan.md)
   - Make operational knobs explicit before packaging or expanding agent-side
     automation.
6. [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/release-and-setup-packaging-plan.md)
   - Establish the release artifact and setup contract before broader installer
     matrix work.
7. [installer-ecosystem-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/installer-ecosystem-parity-plan.md)
   - Expand agent coverage only after shared packaging and client behavior are
     stable.
8. [09-operations-script-suite-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/09-operations-script-suite-plan.md)
   - Operational credibility belongs after the runtime, packaging, and install
     contracts stop moving.
9. [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md)
    - This is the first concrete parser-backed language-expansion tranche.
10. [08-hybrid-type-resolution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md)
    - Hybrid resolution is higher risk and should land only after the repo has a
      stronger parser-backed baseline and cleaner runtime semantics.
11. [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
    - Use this as the broader post-tranche language queue after Plan 07 proves
      the next parser-backed slice.
12. [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
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

The current active plan is
[parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/parser-accuracy-and-graph-fidelity-improvements-plan.md).
When it finishes, the next plan to start is
[discovery-indexing-scope-and-query-semantics-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/discovery-indexing-scope-and-query-semantics-improvements-plan.md).
