# Progress: Semantic Graph Expansion Feature Cluster

## Scope

Bound this plan to one verified semantic tranche:

- explicit `routes.zig` helpers for route-node identity and creation
- explicit `semantic_links.zig` synthesis for pub-sub topic nodes and
  `EMITS` / `SUBSCRIBES` edges
- architecture and trace visibility for the new message facts
- fixture-backed verification only; no higher-order blast-radius or community
  summaries in this slice

## Dependency Order

1. route identity helpers
2. async topic-link synthesis on top of route facts
3. architecture and trace surfacing for those facts
4. only after that: optional higher-order analytics

## Deferred Until After This Plan

- community detection and graph summaries
- compound semantic query helpers beyond `query_graph`, `trace_call_path`, and
  `get_architecture`
- broader framework-specific route registrars beyond the current fixture-backed
  patterns
- richer indirect-call families that do not resolve through the current route or
  async substrate

## Verification Targets

- `zig build`
- `zig build test`
- fixture-level CLI indexing and Cypher queries for
  `testdata/interop/semantic-expansion/http_routes`
- fixture-level CLI indexing, Cypher queries, and `get_architecture` calls for
  `testdata/interop/semantic-expansion/pubsub_events`
