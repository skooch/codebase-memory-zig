# Progress: Graph Enrichment Parity

## 2026-04-16
- Resumed the paused umbrella enrichment plan into
  `docs/plans/in-progress/ready-to-go/04-graph-enrichment-parity-plan.md`.
- Moved the route and config follow-on plans into
  `docs/plans/in-progress/follow-ons/`.
- Reconciled the old bundled scope with the completed graph-model parity plan:
  git-history, route/config fixture parity, route-linked data flow, async route
  callers, and route summaries are already implemented for the verified
  graph-model fixture contract.
- Selected the route graph follow-on as the first execution target.
- Started the route follow-on probe phase and recorded the first findings:
  JavaScript and Python route-registration call candidates currently produce
  Zig-only route rows, while the first raw Python `httpx` caller candidate
  produced Zig-only `HTTP_CALLS` / `DATA_FLOWS` rows.
- Promoted the first strict shared route follow-on fixture:
  `testdata/interop/route-expansion/httpx_stub/` as manifest id
  `route-expansion-httpx`.
- Verified the promoted fixture in targeted `--update-golden`, `--zig-only`,
  and full C-vs-Zig alignment runs. The accepted shared contract is:
  `/api/users` `Route`, `users_endpoint -> /api/users` `HANDLES`,
  `fetch_users -> /api/users` `HTTP_CALLS`, and
  `fetch_users -> users_endpoint` route-linked `DATA_FLOWS`.
- The C reference still emits extra `app.py` caller rows for this fixture, so
  the strict shared assertions intentionally filter the caller side to
  `a.name = 'fetch_users'`.

## Verification
- Route probe verification is recorded in
  `docs/plans/implemented/route-graph-parity-progress.md`.

## 2026-04-17
- Completed the route follow-on child plan and moved it under
  `docs/plans/implemented/`.
- Added a direct duplicate-suppression regression in `src/pipeline.zig` to keep
  repeated route-registration emission deduplicated.
- Verified the route child plan with:
  - `zig fmt src/pipeline.zig`
  - `zig build test`
  - `zig build`
  - `bash scripts/run_interop_alignment.sh --zig-only`
  - `bash scripts/run_interop_alignment.sh`
- Current full interop baseline after the route follow-on:
  - `Fixtures: 23`
  - `Comparisons: 179`
  - `Strict matches: 102`
  - `Diagnostic-only comparisons: 23`
  - `Mismatches: 8`
  - `cli_progress: match`
  - no route-related mismatches remain
- The next active child plan is
  `docs/plans/in-progress/follow-ons/config-linking-and-edge-expansion-plan.md`.
