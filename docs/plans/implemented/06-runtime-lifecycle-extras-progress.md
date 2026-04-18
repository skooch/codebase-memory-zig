# Runtime Lifecycle Extras Progress

## Scope

This plan closes the remaining runtime-lifecycle gap after the completed
shutdown and update-notice slice by implementing the overlapping idle store
lifecycle behavior that still matters for the Zig stdio server.

Current focus:
- timed idle eviction of the shared runtime SQLite handle
- clean reopen of that runtime DB on the next `tools/call`
- live-process verification of the close/reopen cycle
- no reopening of already-completed shutdown and update-notice work

## Phase 1 Contract

### Current baseline from the implementation

- `src.main.runMcpServer` opens a shared runtime DB once at process start and
  keeps it alive for the entire stdio session.
- `src.mcp.runFiles` previously blocked on stdin forever between requests, so
  it had no notion of idle time and no opportunity to release the runtime DB.
- `src.mcp.handleLine` assumed the shared DB stayed open for the full session.
- The Zig runtime already matched the overlapping shutdown and update-notice
  behavior, so this plan should not reopen that earlier lifecycle work.

### Overlap to preserve

- The public overlap is idle release-and-reopen behavior for the runtime store
  while an MCP session remains active.
- The original C runtime achieves that through a per-project cached-store
  mechanism; the Zig runtime uses one shared runtime DB. The storage topology is
  different, but the release/reopen lifecycle is the shared contract we need to
  prove.

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
bash scripts/test_runtime_lifecycle.sh
bash scripts/test_runtime_lifecycle_extras.sh
```

### Red-line thresholds

- Any failure to reopen the runtime DB on the first tool call after an idle
  eviction is a hard failure.
- Any regression in the completed EOF, SIGTERM, or startup update-notice
  checks is a hard failure.
- Any parity claim for idle runtime behavior must be backed by a live stdio
  session check, not only by an in-process unit test.

## Phases

### Phase 1: Lock the Remaining Runtime Contract
- [x] Re-read the original idle-store and session-lifecycle behavior and capture
  the overlapping runtime expectations in `docs/gap-analysis.md`.
- [x] Define the exact idle-session, store-lifecycle, and runtime verification
  workflow in this progress file.
- [x] Keep the scope explicitly limited to the remaining runtime extras instead
  of reopening already completed shutdown and update-notice work.
- **Status:** complete

### Phase 2: Implement Session-Lifecycle Behavior
- [x] Extend `src.main.zig` and `src.mcp.zig` so the Zig runtime can reproduce
  the overlapping idle-store lifecycle behavior from the original without
  reopening the completed shutdown/update-notice slice.
- [x] Add `scripts/test_runtime_lifecycle_extras.sh` so the lifecycle extras
  are testable outside of unit tests.
- [x] Add focused regression coverage for the supported lifecycle transitions
  instead of relying only on ad hoc manual runs.
- **Status:** complete

### Phase 2 Checkpoint: Idle Runtime Store

Implementation on 2026-04-18:

- `src.main.zig`
  - wires the shared runtime DB path into `McpServer`
  - adds `CBM_IDLE_STORE_TIMEOUT_MS` so the idle timeout is controllable during
    verification without changing the default runtime behavior
- `src.mcp.zig`
  - polls stdio with an idle timeout in `runFiles`
  - closes the shared runtime DB after inactivity
  - reopens that runtime DB on the next `tools/call` before dispatch
  - adds a focused unit test that evicts the runtime DB and proves the next
    `list_projects` call reopens it successfully
- `scripts/test_runtime_lifecycle_extras.sh`
  - drives a live stdio server through initialize, first tool call, idle close,
    and second tool call
  - verifies the SQLite handle is visible in `lsof` before idle, absent after
    idle, and visible again after the next tool call

Supported nuance:

- The idle close/reopen contract is verified on the newline-framed stdio MCP
  server. One-shot CLI tool execution opens the runtime DB once and exits, so
  there is no idle window to exercise there.

### Phase 3: Verify and Reclassify
- [x] Run `zig build`, `zig build test`, and
  `bash scripts/test_runtime_lifecycle_extras.sh` until the overlapping
  idle-store and session-lifecycle behavior is green.
- [x] Update `docs/port-comparison.md` so the remaining runtime-extras row
  moves out of `Partial` only after the lifecycle extras are verified.
- [x] Record the final verification transcript and any intentionally unsupported
  runtime nuances in this progress file.
- **Status:** complete

## Phase 3 Completion Pass

Final plan verification on 2026-04-18:

```sh
zig build
zig build test
bash scripts/test_runtime_lifecycle.sh
bash scripts/test_runtime_lifecycle_extras.sh
```

Results:

- `zig build` passed
- `zig build test` passed
- `bash scripts/test_runtime_lifecycle.sh` passed:
  - clean EOF shutdown
  - SIGTERM shutdown
  - one-shot startup update notice
- `bash scripts/test_runtime_lifecycle_extras.sh` passed:
  - runtime DB starts open for the stdio session
  - runtime DB closes after the idle timeout
  - runtime DB reopens on the next `tools/call`
  - live session responses remain valid across the idle close/reopen cycle

Remaining intentional difference:

- The original C runtime uses a per-project cached-store implementation. The
  Zig runtime keeps a shared runtime DB and now matches the overlapping public
  idle close/reopen behavior on that substrate instead of mirroring the C
  implementation detail exactly.
