# Hybrid Type Resolution Progress

## Scope

This plan closes the remaining hybrid-resolution gap with a bounded first slice
 that focuses on the shared overlap for Go, C, and C++ instead of a broad
 external-tools integration sweep.

Current focus:
- re-read the original hybrid-resolution behavior and identify the overlap that
  the Zig port can reproduce without inventing a brand-new analysis model
- define the external data assumptions, fallback behavior, and fixture surface
  before touching pipeline or registry code
- keep the first slice limited to shared hybrid-resolution behavior rather than
  reopening general language expansion or unrelated graph work

## Phase 1 Contract

Planned discovery work:
- inspect the original repo's hybrid-resolution path for Go, C, and C++
- identify what external artifacts or sidecars the Zig port can accept
- define a bounded fixture set under `testdata/interop/hybrid-resolution/`
- define the fallback behavior when hybrid-resolution data is absent

### Expected verification commands

```sh
bash scripts/bootstrap_worktree.sh /Users/skooch/projects/codebase-memory-zig
zig build
zig build test
```

## Phase 1 Checkpoint: Plan Start

Plan-start pass on 2026-04-19:

- activated the dedicated hybrid-resolution worktree and branch
- moved the plan from `new/ready-to-go` to `in-progress`
- created this progress log before source exploration so the contract can be
  refined in place as the original behavior is reviewed
