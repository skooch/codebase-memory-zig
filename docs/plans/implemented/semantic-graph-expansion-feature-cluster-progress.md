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

## Verification Results

Completed on 2026-04-19:

- `zig build`
- `zig build test`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-http ./zig-out/bin/cbm cli index_repository '{"project_path":"testdata/interop/semantic-expansion/http_routes"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-http ./zig-out/bin/cbm cli query_graph '{"project":"http_routes","query":"MATCH (n) WHERE n.label = \"Route\" RETURN n.name ORDER BY n.name ASC"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-http ./zig-out/bin/cbm cli query_graph '{"project":"http_routes","query":"MATCH (a)-[r:HANDLES]->(b) RETURN a.name, b.name ORDER BY a.name, b.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-http ./zig-out/bin/cbm cli query_graph '{"project":"http_routes","query":"MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name ORDER BY a.name, b.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli index_repository '{"project_path":"testdata/interop/semantic-expansion/pubsub_events"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli query_graph '{"project":"pubsub_events","query":"MATCH (n) WHERE n.label = \"EventTopic\" RETURN n.name ORDER BY n.name ASC"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli query_graph '{"project":"pubsub_events","query":"MATCH (a)-[r:EMITS]->(b) RETURN a.name, b.name ORDER BY a.name, b.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli query_graph '{"project":"pubsub_events","query":"MATCH (a)-[r:SUBSCRIBES]->(b) RETURN a.name, b.name ORDER BY a.name, b.name"}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli get_architecture '{"project":"pubsub_events","aspects":["message_summaries"]}'`
- `CBM_CACHE_DIR=/Users/skooch/projects/worktrees/semantic-graph-expansion/.cbm-cache-pubsub ./zig-out/bin/cbm cli trace_call_path '{"project":"pubsub_events","function_name":"enqueue_users","mode":"cross_service","depth":4}'`

Observed results:

- `http_routes` indexed with `9` nodes and `13` edges
- `http_routes` returned `Route = /api/orders`, `HANDLES = listOrders -> /api/orders`, and `HTTP_CALLS = fetchOrders -> /api/orders`
- `pubsub_events` indexed with `7` nodes and `9` edges
- `pubsub_events` returned `EventTopic = users.refresh`, `EMITS = enqueue_users -> users.refresh`, and `SUBSCRIBES = refresh_users -> users.refresh`
- `get_architecture(aspects=["message_summaries"])` returned `emitters=["enqueue_users"]` and `subscribers=["refresh_users"]`
- `trace_call_path(mode="cross_service")` from `enqueue_users` traversed `ASYNC_CALLS`, `DATA_FLOWS`, `EMITS`, and `SUBSCRIBES`
