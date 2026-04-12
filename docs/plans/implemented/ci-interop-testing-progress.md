# A15: CI Interop Testing — Progress Log

## 2026-04-12

- Completed interop testing architecture review (`docs/interop-testing-review.md`)
- Identified 13 issues across 4 themes
- Created execution plan with 7 phases (`docs/plans/new/ci-interop-testing.md`)
- Key finding: 4/13 MCP tools (31%) have zero behavioral coverage in interop harness
- Key finding: nightly CI comparison uses `continue-on-error: true`, making failures invisible
- Key finding: 20 query_graph assertions across 4 parity fixtures accept empty results where golden snapshots have data
- Mapped exact manifest indices and golden snapshot values for required_rows_min fixes
- Identified that I1 (4 uncovered tools) requires harness code changes, not just manifest entries — build_requests, check_assertions, canonical functions, and golden snapshot support all need updates
