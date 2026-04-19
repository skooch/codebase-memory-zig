# Remaining Backlog Order

Refresh date: 2026-04-19

The current target contract, the shared follow-on parity slices, and the
verification-remediation slice are complete. The next queue is the optional
parity and comparison backlog, ordered by leverage and boundedness rather than
by “biggest possible project.”

## Current State

- There are five queued execution plans under `docs/plans/new/`.
- The last ordered plan,
  [semantic-graph-expansion-feature-cluster-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/semantic-graph-expansion-feature-cluster-plan.md),
  is now implemented.
- The most recent completed maintenance slice is
  [verification-remediation-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/implemented/verification-remediation-plan.md).
- Remaining work outside the queue below is still unqueued future expansion
  rather than tracked backlog.

## Next Queue

1. [01-full-compare-mismatch-reduction-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/01-full-compare-mismatch-reduction-plan.md)
   Reduce the currently observed full Zig-vs-C mismatch set first, so the next parity work starts from the smallest bounded debt with the clearest success metric.
2. [02-cypher-and-query-parity-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/02-cypher-and-query-parity-expansion-plan.md)
   Expand the read-only `query_graph` contract after the immediate mismatch cleanup, because fuller Cypher parity is the largest remaining core-query gap called out by the comparison docs.
3. [03-search-and-snippet-contract-normalization-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/03-search-and-snippet-contract-normalization-plan.md)
   Normalize `search_graph` and `get_code_snippet` behavior once the bounded mismatch set and the broader query floor are in better shape.
4. [04-route-and-cross-service-framework-expansion-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/04-route-and-cross-service-framework-expansion-plan.md)
   Add the next bounded route and cross-service framework tranche after the current core query and search contracts are more settled.
5. [05-config-normalization-and-reads-writes-contract-plan.md](/Users/skooch/projects/codebase-memory-zig/docs/plans/new/05-config-normalization-and-reads-writes-contract-plan.md)
   Finish the next shared config-linking and `WRITES` / `READS` contract tranche after the higher-leverage query and route work is queued.
