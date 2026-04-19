# Remaining Backlog Order

Refresh date: 2026-04-19

The current target contract, the shared follow-on parity slices, the
verification-remediation slice, and the bounded full-compare mismatch-reduction
slice are complete. The remaining queue stays ordered by leverage and
boundedness rather than by “biggest possible project.”

## Current State

- There are four queued execution plans under `docs/plans/new/`.
- The last ordered plan,
  [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/semantic-graph-expansion-feature-cluster-plan.md),
  is now implemented.
- The most recent completed maintenance slices are
  [verification-remediation-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/verification-remediation-plan.md)
  and
  [01-full-compare-mismatch-reduction-plan.md](/Users/skooch/projects/worktrees/full-compare-mismatch-reduction/docs/plans/implemented/01-full-compare-mismatch-reduction-plan.md).
- There is no active execution plan in `docs/plans/in-progress/` right now.
- Remaining work outside the queue below is still unqueued future expansion
  rather than tracked backlog.

## Next Queue

1. [02-cypher-and-query-parity-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/02-cypher-and-query-parity-expansion-plan.md)
   Expand the read-only `query_graph` contract after the immediate mismatch cleanup, because fuller Cypher parity is the largest remaining core-query gap called out by the comparison docs.
2. [03-search-and-snippet-contract-normalization-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/03-search-and-snippet-contract-normalization-plan.md)
   Normalize `search_graph` and `get_code_snippet` behavior once the bounded mismatch set and the broader query floor are in better shape.
3. [04-route-and-cross-service-framework-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/04-route-and-cross-service-framework-expansion-plan.md)
   Add the next bounded route and cross-service framework tranche after the current core query and search contracts are more settled.
4. [05-config-normalization-and-reads-writes-contract-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/05-config-normalization-and-reads-writes-contract-plan.md)
   Finish the next shared config-linking and `WRITES` / `READS` contract tranche after the higher-leverage query and route work is queued.
