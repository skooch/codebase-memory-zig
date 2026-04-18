# Large-Repo Reliability and Crash Safety Progress

## Scope

This plan hardens the Zig port against scale-sensitive failures that only show
up when repositories, request payloads, or background lifecycle work get large
enough to stress current assumptions.

Current focus:
- memory growth during extraction and graph-store writes
- oversized request or query buffering
- watcher and lifecycle determinism under slow work
- local stress verification that does not depend on downloading external repos

## Phase 1 Contract

### Current baseline from the implementation

- `src.pipeline.collectExtractionsParallel` allocates one result slot per
  discovered file and only merges results after all worker threads join.
- `src.graph_buffer.dumpToStore` writes the full buffered node and edge set in
  one pass with an in-memory id remap and no chunk boundary.
- `src.store.beginImmediate` / `commit` / `rollback` are minimal wrappers, so
  transaction safety is only as strong as the call sites around them.
- `src.mcp.runFiles` uses newline framing but currently has no explicit cap on
  the size of a single pending request line.
- `src.watcher.pollOnce` keeps the watcher mutex held while it checks git
  state, runs the index callback, and refreshes baseline metadata.

### Local stress inventory

- `testdata/bench/stress-manifest.json`
  - local-only benchmark manifest for repeatable stress lanes
- `testdata/bench/stress/README.md`
  - documents why each local lane exists and how it should be interpreted

Initial local lanes:
- repo self-index lane
  - indexes the Zig repo itself to exercise the current pipeline, watcher
    surfaces, and MCP query path on a medium-sized real codebase
- vendored SQLite lane
  - indexes `vendored/sqlite3` to stress large single-file traversal and bulk
    store writes without depending on an external monorepo checkout

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json
bash scripts/test_runtime_lifecycle.sh
```

### Target metrics and red-line thresholds

- Any panic, segfault, allocator failure, or SQLite corruption/busy error during
  the stress benchmark run is a hard failure.
- Any benchmark lane that fails to emit a report entry or exits non-zero is a
  hard failure.
- Any runtime lifecycle check that exceeds the script's built-in 5 second EOF or
  SIGTERM shutdown window is a hard failure.
- Measured benchmark runs must record elapsed time and, where supported by the
  harness, `max_rss` so later phases can compare growth instead of hand-waving.
- Phase 1 only records the baseline; later phases may tighten the numeric caps
  after the first stress reports exist.

## Phases

### Phase 1: Lock the Stress and Failure Matrix
- [x] Convert the upstream crash classes into a Zig-side reproduction matrix in
  `docs/gap-analysis.md`, separating memory pressure, traversal overflow, store
  corruption, and lifecycle hangs.
- [x] Add a local stress manifest and documentation under `testdata/bench/stress/`
  so large-repo checks are reproducible without external monorepos.
- [x] Record target metrics, red-line thresholds, and exact verification
  commands in this progress file.
- **Status:** complete

### Phase 2: Add Explicit Guardrails
- [ ] Strengthen `src/pipeline.zig`, `src/graph_buffer.zig`, and `src/store.zig`
  with explicit size guards, early-release points, crash-safe transactional
  behavior, and growable traversal state where current design still assumes
  moderate file or result sizes.
- [x] Tighten the first runtime-facing guardrails in `src/mcp.zig` and
  `src/watcher.zig` so oversized request lines fail cleanly and watcher polling
  no longer holds the mutex while running git probes or the indexing callback.
- [ ] Continue tightening `src/runtime_lifecycle.zig` status reporting and load
  behavior so runtime state stays deterministic under stress.
- [ ] Add backpressure, timeout, and oversized-response behavior that fails
  cleanly and observably rather than silently truncating or wedging the runtime.
- **Status:** in_progress

## Phase 2 Checkpoint: Runtime Guardrails

First Phase 2 code slice on 2026-04-18:

- `src.mcp.runFiles`
  - added a `1 MiB` request-line cap for stdio framing
  - emits a deterministic MCP error response for oversized lines
  - discards the remainder of the oversized line until newline, then resumes
    processing subsequent requests
- `src.watcher.pollOnce`
  - snapshots due entries under lock, then performs baseline probing, git
    checks, and the index callback outside the mutex
  - reapplies state updates only after reacquiring the mutex and relocating the
    live entry by project/root path
- tests
  - added a regression test proving `runFiles` rejects an oversized line and
    still processes the next newline-delimited request

Verification for this slice:

```sh
zig build test
bash scripts/test_runtime_lifecycle.sh
```

Results:

- `zig build test` passed
- `bash scripts/test_runtime_lifecycle.sh` passed:
  - clean EOF shutdown
  - SIGTERM shutdown
  - one-shot startup update notice

What remains in Phase 2 after this slice:

- pipeline/graph-buffer/store memory and transaction guardrails
- explicit oversized-response and timeout handling beyond request-line framing
- any additional runtime-lifecycle stress hooks that the later benchmark lanes
  prove necessary

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, `bash scripts/run_benchmark_suite.sh`,
  and `bash scripts/test_runtime_lifecycle.sh` with the new stress cases until
  resource usage and failure handling stay bounded.
- [ ] Update `docs/port-comparison.md` only for the rows that have explicit
  stress evidence rather than anecdotal "seems stable" claims.
- [ ] Record remaining scale risks, skipped stress lanes, and next follow-on
  work in this progress file.
- **Status:** pending

## Initial Baseline Probe

Controlled baseline run on 2026-04-18 after Phase 1 setup:

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
bash scripts/test_runtime_lifecycle.sh
bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json
```

Results:

- `bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig`
  completed successfully
- `bash scripts/test_runtime_lifecycle.sh` passed:
  - clean EOF shutdown
  - SIGTERM shutdown
  - one-shot startup update notice
- `bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json`
  completed successfully and wrote:
  - `.benchmark_reports/benchmark_report.json`
  - `.benchmark_reports/benchmark_report.md`

Measured stress baseline from `.benchmark_reports/benchmark_report.md`:

- `self-repo`
  - Zig cold index median: `2590.476 ms`
  - C cold index median: `23238.584 ms`
  - Zig query medians:
    - `search_graph(function-search)`: `22.743 ms`
    - `get_code_snippet(runtime-snippet)`: `15.205 ms`
    - `get_architecture(watcher-architecture)`: `31.648 ms`
- `sqlite-amalgamation`
  - Zig cold index median: `156.996 ms`
  - C cold index median: `12361.503 ms`
  - Zig query medians:
    - `search_code(search-sqlite-step)`: `13.385 ms`
    - `search_graph(search-functions)`: `11.637 ms`

Important caveats from this first baseline:

- the local stress manifest is performance-only today, so the benchmark summary
  reports `0.0/0.0` accuracy counts by design
- the first stress run found and validated a real wrapper bug:
  `scripts/run_benchmark_suite.sh` failed under `set -u` when invoked without
  trailing extra args; the wrapper has now been fixed in this worktree
- this baseline establishes repeatable local timing and lifecycle evidence, not
  yet explicit memory caps or failure-injection coverage
