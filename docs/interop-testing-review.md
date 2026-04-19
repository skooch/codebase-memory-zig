# Interop Testing Review

**Date:** 2026-04-20
**Scope:** Current-state review of the interop and parity verification surface after the completed queued parity follow-on work
**Status:** Updated

## Summary

The interop harness is in materially better shape than the 2026-04-12 review described.

Current verified state:
- `zig build test` passes in the execution worktree.
- `bash scripts/run_cli_parity.sh --zig-only` passes.
- `bash scripts/run_interop_alignment.sh --zig-only` passes at `33/33`.
- `bash scripts/run_interop_alignment.sh` now reports no hard mismatches instead of the earlier six-item set.
- The current full compare baseline is `33` fixtures, `251` comparisons, `143` strict matches, `38` diagnostic-only comparisons, and `0` mismatches.
- The nightly workflow no longer hides failures behind `continue-on-error`.

The review from 2026-04-12 is no longer accurate as a live issue register. Several items it flagged have already been resolved in the repo, and the remaining debt is narrower than that review implied.

## Current Coverage Surface

### Harnesses

| Script | Purpose | Current role |
|--------|---------|--------------|
| `scripts/run_interop_alignment.sh` | Zig-only golden checks, golden refresh, full Zig-vs-C compare | Primary MCP parity harness |
| `scripts/run_cli_parity.sh` | Installer/config parity via temp-home fixtures | Primary CLI parity harness |
| `scripts/test_runtime_lifecycle.sh` | Runtime lifecycle verification | Separate runtime contract coverage |

### Fixture Footprint

Current manifest footprint:
- `33` fixtures in `testdata/interop/manifest.json`
- zig-only goldens committed for all manifest fixtures
- basic, parity, graph-model, enrichment, discovery-scope, error-path, language-expansion, route-expansion, semantic-expansion, and config-expansion coverage all present

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

This closes the largest blind spot from the earlier review: the shared tool surface is no longer only presence-checked through `tools/list`.

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

## Remaining Verification Debt

The remaining debt is real, but it is narrower:

1. Full Zig-vs-C comparison is still nightly or manual, not a per-PR required gate.
   The repo relies on zig-only goldens for merge blocking, with full reference comparison as a scheduled deeper check.

2. Golden maintenance remains an operational requirement.
   When the canonical representation changes intentionally or new fixtures are added, the harness needs corresponding golden refreshes. The verification-remediation plan already had to restore missing and stale goldens for `python-parity`, `discovery-scope`, `python-framework-cases`, and `typescript-import-cases`.

3. Compare mode now scores shared contract parity rather than implementation-specific payload shape.
   This is most visible where fixture expectations use `required_names`, `required_rows`, or snippet-source floors instead of exhaustively asserting every row shape or qualified-name format. That is acceptable, but it means the golden layer still carries most of the strict regression burden while compare mode focuses on genuine shared-surface divergence.

4. Search request translation is inherently assertion-level.
   `search_graph` still maps a shared manifest contract onto different request shapes (`label` for the C reference, `label_pattern` for Zig). That is now documented inline in the harness, but it remains a designed comparison asymmetry rather than strict payload identity.

5. Compare mode still intentionally permits bounded diagnostic drift.
   The former `go-parity/query_graph` hard mismatch is now scored as diagnostic-only because the shared contract no longer over-asserts the `Class -> DEFINES_METHOD -> Method` row. That keeps the full compare focused on genuine shared-surface failures rather than intentional extraction differences outside the asserted floor.

6. The old discovery-scope warning is resolved.
   The direct Zig/C repro and the full compare both now show `search_code` agreement on the `discovery-scope` fixture: `scopeVisible` returns `src/index.ts`, while `ghostIgnoredHit`, `generatedBundleHit`, and `ghostNestedHit` all return zero results on both implementations. The earlier docs overstated a divergence that is no longer present in the measured baseline.

## Current Judgment

The interop and parity verification surface is now strong enough to support the repo's documented daily-use contract:

- all shared MCP tools are behavior-tested somewhere in the manifest
- the shared `query_graph` contract is now behavior-tested past simple counts, including bounded `DISTINCT`, boolean-precedence filters, numeric property predicates, and edge-type filtering
- the bounded Go hybrid-resolution sidecar contract is now exercised on both the original single-call fixture and the expanded multi-document fixture
- the broader route surface now explicitly includes one additional strict shared framework slice via `route-expansion-httpx`, while `keyword_request_styles` and `semantic-expansion-send-task` stay diagnostic-only by design
- the shared long-tail edge floor now explicitly includes bounded zero-row `WRITES` / `READS` coverage across the exercised Python, JavaScript, TypeScript, and local-state micro-cases
- zig-only golden verification is green
- CLI parity verification is green
- nightly full reference comparison is visible rather than silent

What it still is not:

- exhaustive of every framework permutation
- exhaustive of every error-path shape across every tool
- a per-PR hard gate on the full Zig-vs-C reference comparison

That is acceptable as long as the repo continues to describe the verification posture honestly in `docs/port-comparison.md` and `docs/gap-analysis.md`.
