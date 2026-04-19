# Graph Expansion Roadmap

## Implemented First Tranche

- explicit `routes.zig` helpers now own route-node identity and creation
- explicit `semantic_links.zig` now synthesizes `EventTopic` nodes plus
  `EMITS` / `SUBSCRIBES` edges from verified async route facts
- `get_architecture` can now return `message_summaries`
- `trace_call_path(mode="cross_service")` now traverses `EMITS` and
  `SUBSCRIBES` in addition to HTTP, async, and data-flow edges

## Verified Fixture Surface

- HTTP route registration and HTTP client rendezvous on
  `testdata/interop/semantic-expansion/http_routes`
- Pub-sub topic production and consumption on
  `testdata/interop/semantic-expansion/pubsub_events`

## Deferred Follow-Ons

- higher-order graph analytics such as communities and blast-radius summaries
- richer indirect-call families that do not already collapse onto verified route
  or async facts
- broader framework-specific route or broker registration beyond the current
  decorator and call-pattern coverage
- dedicated compound semantic query helpers beyond `query_graph`,
  `trace_call_path`, and `get_architecture`
