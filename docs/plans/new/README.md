# Remaining Backlog Order

Refresh date: 2026-04-18

The current target contract and the shared follow-on parity slices are complete.
Everything left in `docs/plans/new/` is optional follow-on work. None of these
plans has started yet; when work begins, move the chosen plan into
`docs/plans/in-progress/` in the same change that starts implementation.

## Ordering Principles

- Fix correctness and contract drift before broadening surface area.
- Harden runtime and client behavior before widening product claims.
- Ship packaging before broader installer-ecosystem expansion.
- Add parser-backed language breadth before LSP-assisted or higher-order graph
  expansion.

## Recommended Execution Order

1. [parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-plan.md)
   - First because wrong graph facts poison every later search, trace, semantic,
     and installer claim.
2. [discovery-indexing-scope-and-query-semantics-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/discovery-indexing-scope-and-query-semantics-improvements-plan.md)
   - Next because search and schema behavior need deterministic indexed scope
     before more data or more clients are added.
3. [large-repo-reliability-and-crash-safety-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/large-repo-reliability-and-crash-safety-improvements-plan.md)
   - Third because scale failures, hangs, and corruption invalidate any broader
     adoption story.
4. [06-runtime-lifecycle-extras-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/06-runtime-lifecycle-extras-plan.md)
   - Build on the existing runtime work once correctness and scale boundaries are
     clearer.
5. [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/windows-installer-and-client-integration-improvements-plan.md)
   - Normalize startup, path, and client behavior before claiming a wider
     install surface.
6. [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-plan.md)
   - Make operational knobs explicit before packaging or expanding agent-side
     automation.
7. [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/release-and-setup-packaging-plan.md)
   - Establish the release artifact and setup contract before broader installer
     matrix work.
8. [installer-ecosystem-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/installer-ecosystem-parity-plan.md)
   - Expand agent coverage only after shared packaging and client behavior are
     stable.
9. [09-operations-script-suite-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/09-operations-script-suite-plan.md)
   - Operational credibility belongs after the runtime, packaging, and install
     contracts stop moving.
10. [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/07-language-coverage-expansion-plan.md)
    - This is the first concrete parser-backed language-expansion tranche.
11. [08-hybrid-type-resolution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md)
    - Hybrid resolution is higher risk and should land only after the repo has a
      stronger parser-backed baseline and cleaner runtime semantics.
12. [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
    - Use this as the broader post-tranche language queue after Plan 07 proves
      the next parser-backed slice.
13. [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
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

If we start the remaining backlog now, begin with
[parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/parser-accuracy-and-graph-fidelity-improvements-plan.md).
