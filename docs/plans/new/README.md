# Remaining Backlog Order

Refresh date: 2026-04-19

The current target contract and the shared follow-on parity slices are complete.
Everything left in `docs/plans/new/` is optional follow-on work.

## Ordering Principles

- Fix correctness and contract drift before broadening surface area.
- Harden runtime and client behavior before widening product claims.
- Ship packaging before broader installer-ecosystem expansion.
- Add parser-backed language breadth before LSP-assisted or higher-order graph
  expansion.

## Recommended Execution Order

1. [08-hybrid-type-resolution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md)
   - Hybrid resolution is higher risk and should land only after the repo has a
     stronger parser-backed baseline and cleaner runtime semantics.
2. [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
   - Use this as the broader post-tranche language queue after Plan 07 proves
     the next parser-backed slice.
3. [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
   - Keep higher-order graph expansion last, after graph correctness, scale,
     and language posture are stronger.

## Dependency Notes

- [07-language-coverage-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/07-language-coverage-expansion-plan.md) is complete.
  [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
  is the broader queue and should not start first.
- [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/windows-installer-and-client-integration-improvements-plan.md)
  is complete, which cleared its prerequisite role for the completed
  installer-ecosystem plan.
- [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/operational-controls-and-configurability-feature-cluster-plan.md)
  is complete, which clears packaging as the next active productization step.
- [release-and-setup-packaging-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/release-and-setup-packaging-plan.md)
  landed before the completed installer-ecosystem plan.
- [09-operations-script-suite-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/09-operations-script-suite-plan.md)
  is complete, which closes the bounded repo-owned operations credibility
  slice before the remaining language-expansion work.
- [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
  assumes the discovery/query, reliability, and language contracts are already
  firmer than they are today.

## Start Here

The next unopened plan is
[08-hybrid-type-resolution-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/ready-to-go/08-hybrid-type-resolution-plan.md).
