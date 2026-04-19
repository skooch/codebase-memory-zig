# Progress

## Session: 2026-04-20

### Phase 1: Choose the next bounded framework tranche
- **Status:** completed
- Actions:
  - Created the route and cross-service framework-depth plan as backlog item `05`.
  - Reviewed the current shared and diagnostic framework fixtures instead of assuming the docs were current.
  - Measured the existing route and broker follow-on fixtures in a fresh full compare and selected the `route-expansion-httpx` Python slice as the next bounded shared tranche.
  - Confirmed the selected shared overlap is:
    - `Route` node `"/api/users"`
    - `HANDLES` row `users_endpoint -> /api/users`
    - `HTTP_CALLS` row `fetch_users -> /api/users`
    - route-linked `DATA_FLOWS` row `fetch_users -> users_endpoint`
  - Recorded explicit non-goals for this pass:
    - `keyword_request_styles`
    - `celery_send_task`
    - any new extractor or router expansion beyond the already implemented `httpx` slice
- Files modified:
  - `docs/plans/implemented/05-route-and-cross-service-framework-depth-plan.md`
  - `docs/plans/implemented/05-route-and-cross-service-framework-depth-progress.md`

### Phase 2: Implement the next route and broker slice
- **Status:** completed
- Actions:
  - Determined that no extractor, pipeline, route-helper, semantic-link, or query-router code changes were required for the selected tranche.
  - Verified from the current harness output that `route-expansion-httpx` already full-compares as `match`, while `keyword_request_styles` and `semantic-expansion-send-task` remain `diagnostic` because the C reference still returns empty row sets for those queries.
  - Chose to promote only the already-green `httpx` overlap into the public docs instead of widening the shared contract past measured evidence.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

### Phase 3: Rebaseline framework-depth claims
- **Status:** completed
- Actions:
  - Completed `zig build`, `zig build test`, `bash scripts/run_interop_alignment.sh --zig-only`, and `bash scripts/run_interop_alignment.sh`.
  - Measured the unchanged full-compare baseline at:
    - `33` fixtures
    - `251` comparisons
    - `143` strict matches
    - `38` diagnostic-only comparisons
    - `0` mismatches
    - `cli_progress: match`
  - Rebased the comparison docs to say explicitly that `route-expansion-httpx` is already part of the strict shared route contract, while the keyword-route and `celery.send_task` slices remain diagnostic-only.
- Files modified:
  - `docs/port-comparison.md`
  - `docs/gap-analysis.md`
  - `docs/interop-testing-review.md`
  - `docs/plans/new/README.md`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
