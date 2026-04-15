# Graph Model Parity Progress

## Session: 2026-04-16

### Phase 1: Lock the Remaining Graph Contract
- **Status:** partially complete
- Actions:
  - Moved `docs/plans/new/graph-model-parity-plan.md` to `docs/plans/in-progress/graph-model-parity-plan.md` before implementation.
  - Starting from current main baseline: full Zig-vs-C harness reports 151 comparisons, 86 strict matches, 19 diagnostic-only comparisons, and 10 known mismatches.
  - Re-read the original route-node and service-pattern route registration paths and selected the first shared public contract: decorator-backed routes create `Route` nodes and `HANDLES` edges, with query-visible handler and route rows.
  - Added `testdata/interop/graph-model/routes/app.py` and manifest assertions for `Route` and `HANDLES` query rows.

### Phase 2: Complete Route Handler Modeling
- **Status:** in progress
- Actions:
  - Extended extractor state so route decorators create `Route` nodes plus `HANDLES` edges during extraction.
  - Added route-registration call metadata for framework calls such as `app.get("/path", handler)` and pipeline emission for `Route`, `CALLS`, and `HANDLES` when the handler resolves.
  - Added focused unit coverage in `src/extractor.zig`, `src/pipeline.zig`, and `src/service_patterns.zig`.
  - Updated Zig golden snapshots; new `graph-model-routes` golden locks `/users` and `list_users -> /users`.

### Phase 3: Add Route-Linked Data Flow
- **Status:** partially complete
- Actions:
  - Added first-string call-argument capture for unresolved calls so route-like URL/path arguments can become graph facts.
  - Updated service-route call handling so supported HTTP/async service calls with URL/path arguments emit caller edges to concrete `Route` nodes instead of only targeting library functions.
  - Added URL-argument route detection for resolved normal calls, matching the original `arg_url` route pathway for local call wrappers.
  - Added `DATA_FLOWS` creation in `src/route_nodes.zig` by linking `HTTP_CALLS`/`ASYNC_CALLS` edges targeting a `Route` to `HANDLES` edges targeting the same `Route`, skipping self and direct-call duplicates.
  - Verified the focused fixture locally with `zig build run -- cli query_graph`: `fetch_users` has `HTTP_CALLS` to `/api/users`, `list_users` has `HANDLES` for `/api/users`, and `fetch_users` has `DATA_FLOWS` to `list_users`.
  - Kept the strict shared manifest assertions to `Route` and `HANDLES` rows because the current C reference binary does not emit the `DATA_FLOWS` row for this public fixture.

### Verification
- `zig build` -> passed
- `zig build test` -> passed
- `bash scripts/run_interop_alignment.sh --update-golden` -> passed, 20/20 golden snapshots updated
- `bash scripts/run_interop_alignment.sh --zig-only` -> passed, 20/20 golden comparison
- `bash scripts/run_interop_alignment.sh` -> passed with 20 fixtures, 158 comparisons, 89 strict matches, 20 diagnostic-only comparisons, 10 known mismatches, and `cli_progress: match`

## Errors
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-04-16 | Initial `graph-model-routes` manifest used a Zig project name that did not match the indexed directory basename, so query assertions read an empty project. | Ran `--update-golden` and inspected the generated `graph-model-routes` snapshot. | Changed the fixture project to `routes`, regenerated golden snapshots, and verified query rows were populated. |
| 2026-04-16 | JavaScript route-registration fixture improved Zig but was not emitted by the current C binary, adding a new full-harness mismatch. | Ran the full Zig-vs-C harness and inspected per-fixture route outputs. | Switched the strict shared fixture to a Python decorator route that both implementations expose publicly, while keeping Zig registration support covered by unit tests. |
| 2026-04-16 | The redirected harness rerun wrapper used `status`, which is read-only in zsh. | Tried to capture the exit code with `status=$?`. | Re-ran with `rc=$?`; both `--zig-only` and full interop passed. |
| 2026-04-16 | Running `zig fmt` on the Python fixture reported a syntax error because `zig fmt` only accepts Zig input. | Included `testdata/interop/graph-model/routes/app.py` in the formatter command. | Re-ran formatting on Zig files only and validated the manifest separately with `python3 -m json.tool`. |
| 2026-04-16 | The decorator route emitter kept a graph node pointer across a `Route` upsert, which could reallocate the node array and crash while formatting handler properties. | Focused CLI indexing of the route fixture hit an integer-overflow panic in `std.fmt.allocPrint`. | Copied the handler id and qualified name before upserting the route, then re-ran build, tests, and focused CLI query successfully. |
| 2026-04-16 | Adding a strict manifest assertion for the new `DATA_FLOWS` row increased the full C/Zig mismatch count because the current C binary did not emit that row for the public fixture. | Ran full interop and inspected per-implementation `graph-model-routes` query rows. | Removed the `DATA_FLOWS` row from the strict shared manifest while keeping Zig unit/focused coverage and documenting the shared-fixture blocker. |
