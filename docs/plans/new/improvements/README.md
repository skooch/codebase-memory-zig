# Upstream Improvements Plan Set

This directory turns the upstream `codebase-memory-mcp` issue and PR review into concrete Zig-port planning slices.

## Scope

- Reviewed upstream records: `115` issues and `105` PRs opened between `2026-02-25` and `2026-04-11`
- Ignored for theme extraction:
  - pure dependency-update PRs authored by `app/dependabot`
  - repo-process or promotional items that do not materially change product behavior
- Folded into the plan set:
  - recurring bug families
  - recurring feature-request clusters
  - large unmerged expansion PRs that reveal sustained product pressure

These plans are upstream-improvement backlog, not the current parity execution
entrypoint. The graph-model parity plan is complete and archived at
[graph-model-parity-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/graph-model-parity-plan.md).

For the cross-bucket order that includes these improvement plans plus the
remaining ready-to-go and productization plans, use
[../README.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/README.md).

Completed discovery/query contract work is archived at
[../../implemented/discovery-indexing-scope-and-query-semantics-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/discovery-indexing-scope-and-query-semantics-improvements-plan.md).

## Active Improvement Plan

- [parser-accuracy-and-graph-fidelity-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/in-progress/parser-accuracy-and-graph-fidelity-improvements-plan.md)

## Remaining Improvement Queue

- [large-repo-reliability-and-crash-safety-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/large-repo-reliability-and-crash-safety-improvements-plan.md)
- [windows-installer-and-client-integration-improvements-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/windows-installer-and-client-integration-improvements-plan.md)
- [language-support-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/language-support-expansion-feature-cluster-plan.md)
- [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/semantic-graph-expansion-feature-cluster-plan.md)
- [operational-controls-and-configurability-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-plan.md)

## Coverage Notes

- Parser and graph-fidelity work is separated from language-expansion work so supported-language correctness is not blocked on new grammar onboarding.
- Reliability and crash-safety work is separated from Windows and client-integration work so platform fixes do not dilute large-repo hardening.
- Discovery/query-semantics work is separated from semantic-graph expansion so search-contract fixes land before new analysis surfaces depend on them.
