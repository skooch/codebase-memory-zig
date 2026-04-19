# Progress

## Session: 2026-04-19

### Phase 1: Choose the next framework-expansion tranche
- **Status:** completed
- Actions:
  - Created the route and cross-service framework expansion plan as the fourth queued follow-on.
  - Scoped it to a bounded next fixture tranche rather than an open-ended route-expansion backlog.
  - Reviewed the currently green route slices: decorator-backed handler attribution, generic registrar calls, `httpx` caller classification, route-linked `DATA_FLOWS`, async topic routes, and semantic `EMITS`/`SUBSCRIBES`.
  - Chose a bounded next tranche with two concrete patterns already named in the service-pattern table:
    - keyword-based HTTP route registrations such as `add_api_route(..., endpoint=handler, methods=["GET"])` and `add_url_rule(..., view_func=handler, methods=["POST"])`
    - generic request-style dispatch such as `requests.request("GET", "/path")`
    - broker dispatch through `celery.send_task("topic")`
  - Classified the ownership points before implementation:
    - `src/extractor.zig` owns keyword handler and method parsing for route registrations plus second-string call capture
    - `src/pipeline.zig` owns second-string route-target promotion and explicit method inference for generic request calls
    - `src/routes.zig` and `src/semantic_links.zig` do not need new primitives for this tranche because the existing route/topic node synthesis is already sufficient once the new facts are emitted
- Files modified:
  - `docs/plans/in-progress/04-route-and-cross-service-framework-expansion-plan.md`
  - `docs/plans/in-progress/04-route-and-cross-service-framework-expansion-progress.md`

### Phase 2: Implement the next route and message-flow slice
- **Status:** completed
- Actions:
  - Extended extractor parsing for keyword handler attribution and explicit HTTP methods in route registration calls.
  - Extended service-route promotion for request-style calls that carry the method in the first string argument and the route target in the second.
  - Added regression fixtures and unit coverage for keyword route registrations and `celery.send_task`.
  - Added two fixture-backed interop slices:
    - `route-expansion-keyword-request` for `add_api_route(..., endpoint=...)` plus `requests.request("GET", "/api/orders")`
    - `semantic-expansion-send-task` for `celery.send_task("users.refresh")`
  - Verified the new tranche with `zig build test`, `bash scripts/run_interop_alignment.sh --update-golden`, `bash scripts/run_interop_alignment.sh --zig-only`, and a full `bash scripts/run_interop_alignment.sh` compare run.
  - Measured result: zig-only goldens are green on both new fixtures, and the full compare keeps them at `diagnostic` rather than `mismatch` because the current C reference still returns empty row sets while the shared floor scoring does not fail them.
- Files modified:
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `src/query_router_test.zig`
  - `src/store_test.zig`
  - `testdata/interop/manifest.json`
  - `testdata/interop/golden/route-expansion-keyword-request.json`
  - `testdata/interop/golden/semantic-expansion-send-task.json`
  - `testdata/interop/route-expansion/keyword_request_styles/`
  - `testdata/interop/semantic-expansion/celery_send_task/`

### Phase 3: Rebaseline parity evidence and docs
- **Status:** completed
- Actions:
  - Updated `docs/port-comparison.md` and `docs/gap-analysis.md` to the new measured baseline: 30 fixtures, 230 comparisons, 132 strict matches, 34 diagnostic-only comparisons, and 1 remaining hard mismatch.
  - Recorded the new route/framework tranche as verified Zig-side expansion with diagnostic-only full-compare evidence rather than overstating it as strict shared parity.
  - Refreshed `docs/plans/new/README.md` so the next queued execution item is the config-normalization and `WRITES` / `READS` contract plan.
  - Carried forward the stray `adr-parity` golden rebaseline produced by the verified `--update-golden` run so the checked-in snapshots match the current harness output.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
