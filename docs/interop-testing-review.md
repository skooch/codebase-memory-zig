# Interop Testing Review

**Date:** 2026-04-21
**Scope:** Current-state review of the interop and parity verification surface after the completed queued parity follow-on work
**Status:** Updated

## Summary

The interop harness is in materially better shape than the 2026-04-12 review described.

Current verified state:
- `zig build test` passes in the execution worktree.
- `bash scripts/test_runtime_lifecycle.sh` passes.
- `bash scripts/test_runtime_lifecycle_extras.sh` passes.
- `bash scripts/run_cli_parity.sh --zig-only` passes at `112` exact checks.
- `bash scripts/run_cli_parity.sh` passes with `18` shared checks and `0` mismatches.
- `bash scripts/run_interop_alignment.sh --zig-only` passes at `39/39`.
- `bash scripts/run_interop_alignment.sh` now reports no hard mismatches instead of the earlier six-item set.
- The current full compare baseline is `39` fixtures, `301` comparisons, `164` strict matches, `45` diagnostic-only comparisons, and `0` mismatches.
- The full-compare workflow no longer hides failures behind `continue-on-error` and now runs as a path-scoped PR or `main` gate in addition to the weekly scheduled sweep.

The review from 2026-04-12 is no longer accurate as a live issue register. Several items it flagged have already been resolved in the repo, and the remaining debt is narrower than that review implied.

## Current Coverage Surface

### Harnesses

| Script | Purpose | Current role |
|--------|---------|--------------|
| `scripts/run_interop_alignment.sh` | Zig-only golden checks, golden refresh, full Zig-vs-C compare | Primary MCP parity harness |
| `scripts/run_cli_parity.sh` | Installer/config parity via temp-home fixtures | Primary CLI parity harness (`112` exact zig-only checks; `18` shared compare checks) |
| `scripts/test_runtime_lifecycle.sh` | Runtime lifecycle verification | Primary runtime contract harness for EOF shutdown, live `SIGTERM`, update-notice timing, initialized-notification silence, and Windows no-`HOME` cache-root fallback |
| `scripts/test_runtime_lifecycle_extras.sh` | Runtime idle-store lifecycle verification | Separate runtime extras harness for live close/reopen of the shared runtime DB |

### Fixture Footprint

Current manifest footprint:
- `39` fixtures in `testdata/interop/manifest.json`
- zig-only goldens committed for all manifest fixtures
- basic, parity, graph-model, enrichment, discovery-scope, error-path, language-expansion, route-expansion, semantic-expansion, config-expansion, and exact protocol-contract coverage all present

### MCP Tool Assertion Coverage

Current manifest assertion coverage across the shared tool surface:

| Tool | Manifest assertion coverage |
|------|-----------------------------|
| `index_repository` | yes |
| `search_graph` | yes |
| `query_graph` | yes |
| `trace_call_path` | yes |
| `get_architecture` | yes |
| `search_code` | yes |
| `detect_changes` | yes |
| `manage_adr` | yes |
| `list_projects` | yes |
| `get_code_snippet` | yes |
| `get_graph_schema` | yes |
| `index_status` | yes |
| `delete_project` | yes |
| exact `initialize` / `tools/list` / `tools/call` / one-shot CLI contract layer | yes |

This closes the largest blind spot from the earlier review: the shared tool surface is no longer only presence-checked through `tools/list`, and the protocol handshake plus one-shot CLI layer now have dedicated named fixtures.

## Resolved Since The Earlier Review

The following findings from the 2026-04-12 review are no longer current:

- `get_code_snippet`, `get_graph_schema`, `index_status`, and `delete_project` are now exercised by manifest assertions.
- The SCIP fixture is wired into the manifest and golden surface.
- `detect_changes` assertions are no longer vacuous.
- The nightly full-comparison workflow no longer uses `continue-on-error`.
- Progress phase normalization includes `[5/9]`, `[7/9]`, and `[8/9]`, with `[6/9]` explicitly absent.
- Go fixtures exist.
- Error-path coverage exists.
- `zig-parity` exists.
- Golden comparison already includes actual node and edge counts alongside thresholds and warns on significant drops.
- `scripts/run_cli_parity.sh` is executable.
- The shared manifest now also covers the expanded bounded Go hybrid-resolution sidecar slice.
- The shared manifest now also includes exact `protocol-contract` and `tool-surface-parity` fixtures for the public MCP handshake and tool surface.
- Startup watcher registration and startup auto-index now also have direct unit coverage in `src/main.zig`, so those runtime rows are no longer backed only by implementation reading.

## Remaining Verification Debt

The remaining debt is real, but it is narrower:

1. Full Zig-vs-C comparison is now a path-scoped PR or `main` gate rather than a weekly-only check.
   The remaining limitation is scope: non-interop changes still merge on the fast zig-only gate, while interop-touching changes also trigger the heavier reference comparison.

2. Golden maintenance remains an operational requirement.
   When the canonical representation changes intentionally or new fixtures are added, the harness needs corresponding golden refreshes. The verification-remediation plan already had to restore missing and stale goldens for `python-parity`, `discovery-scope`, `python-framework-cases`, and `typescript-import-cases`.

3. Compare mode now scores shared contract parity rather than implementation-specific payload shape.
   This is most visible where fixture expectations use `required_names`, `required_rows`, or snippet-source floors instead of exhaustively asserting every row shape or qualified-name format. That is acceptable, but it means the golden layer still carries most of the strict regression burden while compare mode focuses on genuine shared-surface divergence.

4. Search request translation is inherently assertion-level.
   `search_graph` still maps a shared manifest contract onto different request shapes (`label` for the C reference, `label_pattern` for Zig). That is now documented inline in the harness, but it remains a designed comparison asymmetry rather than strict payload identity.

5. Compare mode still intentionally permits bounded diagnostic drift.
   The old `go-parity/query_graph` and `java-basic/query_graph` language deltas are no longer inside the exercised shared floor; the current Go and Java fixture rows now full-compare cleanly, while compare mode still leaves room for diagnostic-only drift outside asserted contracts in other areas.

6. The old discovery-scope warning is resolved.
   The direct Zig/C repro and the full compare both now show `search_code` agreement on the `discovery-scope` fixture: `scopeVisible` returns `src/index.ts`, while `ghostIgnoredHit`, `generatedBundleHit`, and `ghostNestedHit` all return zero results on both implementations. The earlier docs overstated a divergence that is no longer present in the measured baseline.

7. Latest-upstream tool-surface parity still has one deliberate diagnostic row.
   The new `tool-surface-parity` fixture proves exact inventory/schema coverage for the shared public surface, but it intentionally stays diagnostic-only because Zig still rejects `index_repository(mode="moderate")` while the upstream release accepts it.

## Current Judgment

The interop and parity verification surface is now strong enough to support the repo's documented daily-use contract:

- all shared MCP tools are behavior-tested somewhere in the manifest
- the MCP handshake and tool-surface layer now have dedicated exact fixtures via `protocol-contract` and `tool-surface-parity`
- the query/analysis surface now also has dedicated exact fixtures for snippet or trace behavior, architecture-aspect coverage, and search-code ranking or mode behavior
- the graph-exactness surface now also has dedicated exact fixtures for `TESTS`, `IMPORTS`, `CONFIGURES`, `USES_TYPE`, route-linked `DATA_FLOWS`, `THROWS`/`RAISES`, `SIMILAR_TO`, and `FILE_CHANGES_WITH`
- the runtime lifecycle surface now also has dedicated direct coverage for startup watcher registration and startup auto-index, in addition to the live stdio lifecycle scripts
- the shared `query_graph` contract is now behavior-tested past simple counts, including bounded `DISTINCT`, boolean-precedence filters, numeric property predicates, and edge-type filtering
- the bounded Go hybrid-resolution sidecar contract is now exercised on both the original single-call fixture and the expanded multi-document fixture
- the broader route surface now explicitly includes one additional strict shared framework slice via `route-expansion-httpx`, while `keyword_request_styles` and `semantic-expansion-send-task` stay diagnostic-only by design
- the shared long-tail edge floor now explicitly includes bounded zero-row `WRITES` / `READS` coverage across the exercised Python, JavaScript, TypeScript, and local-state micro-cases
- zig-only golden verification is green
- CLI parity verification is green
- full reference comparison is visible as both a routine gate for interop-touching changes and a weekly scheduled sweep

What it still is not:

- exhaustive of every framework permutation
- exhaustive of every error-path shape across every tool
- an unconditional per-PR hard gate on the full Zig-vs-C reference comparison for every repo change

That is acceptable as long as the repo continues to describe the verification posture honestly in `docs/port-comparison.md` and `docs/gap-analysis.md`.
