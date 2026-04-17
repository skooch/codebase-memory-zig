# Progress: Route Graph Parity Follow-On

## 2026-04-16
- Resumed the old route graph parity plan from paused/superseded into
  `docs/plans/in-progress/follow-ons/route-graph-parity-plan.md`.
- Re-scoped the plan around work that remains after graph-model parity:
  broader route-framework and route-caller fixture coverage beyond the verified
  Python decorator, HTTP caller, async topic, route-linked data-flow, and route
  summary contract.
- Chose this as the first child plan under the graph-enrichment umbrella.
- Ran controlled temporary-fixture probes through
  `bash scripts/run_interop_alignment.sh` against the current Zig and C
  binaries.
- Probed JavaScript route-registration candidates:
  - `app.get("/users", listUsers)`
  - `router.route("/orders", listOrders)`
  - Result: Zig emitted `Route` and `HANDLES` rows; C emitted no matching route
    rows. These are not safe strict shared fixtures today.
- Probed Python route-registration call candidates:
  - `app.get("/users", list_users)`
  - `router.route("/orders", list_orders)`
  - Result: Zig emitted `Route` and `HANDLES` rows; C emitted no matching route
    rows. These are not safe strict shared fixtures today.
- Probed a Python `httpx` route-caller candidate layered on an existing
  decorator-backed handler:
  - Both implementations emitted the decorator-backed `Route` and `HANDLES`
    rows.
  - Zig additionally emitted `fetch_users -> /api/users` over `HTTP_CALLS` and
    `fetch_users -> users_endpoint` over route-linked `DATA_FLOWS`.
  - C emitted neither row, so this is useful Zig-only behavior rather than a new
    strict shared contract.
- Conclusion from the first probe tranche:
  - no new strict shared route-expansion fixture has been identified yet
  - the current verified shared route contract remains the existing
    `graph-model-routes` and `graph-model-async` coverage
  - the next route probe should target a different C-exposed framework or
    caller pattern instead of promoting the first candidate set
- Probed a second Python `httpx` candidate with a local `httpx.py` stub and
  explicit import, mirroring the existing local-stub strategy used by the
  shared `requests` fixture.
  - Both implementations emitted `/api/users` `Route` and
    `users_endpoint -> /api/users` `HANDLES`.
  - Both implementations emitted `fetch_users -> /api/users` over
    `HTTP_CALLS`.
  - Both implementations emitted `fetch_users -> users_endpoint` over
    route-linked `DATA_FLOWS`.
  - The C binary also emitted extra `app.py` caller rows, so the accepted shared
    contract filters the Cypher query to `a.name = 'fetch_users'`.
- Promoted the accepted candidate into the repo as
  `testdata/interop/route-expansion/httpx_stub/` with manifest id
  `route-expansion-httpx`.

## Verification
- Controlled probe runs:
  - `bash scripts/run_interop_alignment.sh /tmp/cbm-route-probe-zpwWx5/probe-manifest.json /tmp/cbm-route-probe-zpwWx5/report`
  - `bash scripts/run_interop_alignment.sh /tmp/cbm-route-probe2-EHLSLM/probe-manifest.json /tmp/cbm-route-probe2-EHLSLM/report`
  - `bash scripts/run_interop_alignment.sh /tmp/cbm-route-probe3-pogVvU/probe-manifest.json /tmp/cbm-route-probe3-pogVvU/report`
  - `bash scripts/run_interop_alignment.sh /tmp/cbm-route-probe4-8sqZ7t/probe-manifest.json /tmp/cbm-route-probe4-8sqZ7t/report`
- Promoted fixture verification:
  - `bash scripts/run_interop_alignment.sh --update-golden /tmp/route-expansion-httpx-manifest-QXhvJj.json`
  - `bash scripts/run_interop_alignment.sh --zig-only /tmp/route-expansion-httpx-manifest-QXhvJj.json`
  - `bash scripts/run_interop_alignment.sh /tmp/route-expansion-httpx-manifest-QXhvJj.json`
- Reports inspected:
  - `/tmp/cbm-route-probe-zpwWx5/report/interop_alignment_report.json`
  - `/tmp/cbm-route-probe2-EHLSLM/report/interop_alignment_report.json`
  - `/tmp/cbm-route-probe3-pogVvU/report/interop_alignment_report.json`
  - `/tmp/cbm-route-probe4-8sqZ7t/report/interop_alignment_report.json`
  - `/Users/skooch/projects/codebase-memory-zig/.interop_reports/interop_golden_report.json`
  - `/Users/skooch/projects/codebase-memory-zig/.interop_reports/interop_alignment_report.json`
