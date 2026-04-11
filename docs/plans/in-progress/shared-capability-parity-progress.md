# Progress

## Session: 2026-04-11

### Phase 1: Lock the Full-Parity Contract and Verification Surface
- **Status:** in progress
- Actions:
  - Moved `docs/plans/new/shared-capability-parity-plan.md` to `docs/plans/in-progress/shared-capability-parity-plan.md` to start execution under the repo's plan convention.
  - Re-read `docs/port-comparison.md`, `docs/gap-analysis.md`, `docs/zig-port-plan.md`, and `scripts/run_interop_alignment.sh` to pin the exact shared-but-not-interoperable surface and the current verification limitations.
  - Re-read the local correction that defines `Interoperable?` as full parity rather than mere feature overlap.
  - Added a new “Shared Capability Full-Parity Follow-On” acceptance section to `docs/gap-analysis.md` so each targeted shared capability now has a concrete parity rule, primary Zig ownership files, and an intended verification path.
  - Added a follow-on shared-parity section to `docs/zig-port-plan.md` so the repo-level roadmap now points at this narrower full-parity plan instead of leaving the post-Phase-7 state as a generic deferred bucket.
  - Expanded `testdata/interop/manifest.json` from 5 fixtures to 9 fixtures and added new parity fixture repos for Python, JavaScript, TypeScript, and Rust with aliasing, semantic-edge, type-reference, and config-touching examples.
  - Validated that the expanded manifest parses as schema version `0.2` with 9 fixtures.
  - Attempted to run `bash scripts/run_interop_alignment.sh` against the enlarged fixture corpus; the run did not yield a new report promptly, so I traced the failure down to Zig MCP stdio transport rather than the fixture corpus itself.
  - Reproduced the stall with direct `initialize` + `index_repository` requests, confirmed the CLI path still worked, and sampled the live process to show `src/mcp.zig` `runFiles` was back in its read loop instead of consuming the second JSON-RPC line.
  - Replaced the stdio `runFiles` delimiter reader with an explicit newline-framed file read loop in `src/mcp.zig` and added a pipe-backed regression test for multiple sequential requests.
  - Isolated both the Zig and C interop runs in per-fixture temp runtimes by setting `HOME` and `CBM_CACHE_DIR` inside `scripts/run_interop_alignment.sh`, eliminating machine-local project cache bleed from `list_projects`.
  - Re-ran `zig build`, `zig build test`, the direct two-request MCP repro, and `bash scripts/run_interop_alignment.sh`; the 9-fixture harness now completes and reports real remaining mismatches in `javascript-parity` search coverage plus `rust-parity` interface/query parity.
  - Confirmed the `javascript-parity` function-search mismatch was a fixture-overlap issue rather than a Zig bug: the original implementation does not surface the named function expression `boot` in `search_graph`, so the harness now only asserts the shared `decorate` result there.
  - Relabeled Rust `trait` extraction from `Trait` to `Interface` in the Zig extractor/test surface so `search_graph` and `query_graph` use the same shared label contract as the original implementation.
  - Re-ran `zig build`, `zig build test`, and `bash scripts/run_interop_alignment.sh` after rebuilding the binary; the current 9-fixture first-gate harness is now fully green with 36 strict matches, 9 diagnostic comparisons, and 0 mismatches while the advanced-tool expansion item remains open.
- Files modified:
  - `docs/plans/in-progress/shared-capability-parity-plan.md`
  - `docs/plans/in-progress/shared-capability-parity-progress.md`
  - `docs/gap-analysis.md`
  - `docs/zig-port-plan.md`
  - `CLAUDE.md`
  - `src/mcp.zig`
  - `src/extractor.zig`
  - `src/pipeline.zig`
  - `scripts/run_interop_alignment.sh`
  - `testdata/interop/manifest.json`
  - `testdata/interop/python-parity/main.py`
  - `testdata/interop/python-parity/models.py`
  - `testdata/interop/python-parity/settings.yaml`
  - `testdata/interop/javascript-parity/index.js`
  - `testdata/interop/javascript-parity/package.json`
  - `testdata/interop/typescript-parity/index.ts`
  - `testdata/interop/typescript-parity/tsconfig.json`
  - `testdata/interop/rust-parity/Cargo.toml`
  - `testdata/interop/rust-parity/src/lib.rs`
