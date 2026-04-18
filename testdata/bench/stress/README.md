# Local Stress Lanes

This directory documents the local-only stress lanes used by
`testdata/bench/stress-manifest.json`.

These lanes are not parity claims. They exist to keep large-repo reliability
checks reproducible inside this repository without requiring a separate
monorepo checkout or network fetch.

## Lanes

### `self-repo`

- Path: `.`
- Purpose:
  - exercise indexing and query behavior against the real Zig codebase
  - keep watcher, MCP, and store paths on a medium-sized local repo
- What to watch:
  - end-to-end index completion
  - report generation
  - query responsiveness after indexing

### `sqlite-amalgamation`

- Path: `vendored/sqlite3`
- Purpose:
  - stress large single-file traversal and graph-store writes against a local
    corpus that is already vendored in the repo
  - expose request and search behavior on a very large C source file without
    depending on GitHub fetches
- What to watch:
  - crashes, panics, or allocator failures during indexing
  - oversized search/snippet behavior on `sqlite3.c`
  - report coverage for elapsed time and `max_rss`

## Standard Run

```sh
bash scripts/run_benchmark_suite.sh testdata/bench/stress-manifest.json
```

## Interpretation

- A green local stress run only means the current implementation stayed bounded
  on these reproducible lanes.
- It does not prove broad large-monorepo parity with the original C runtime.
- Any failure here is a blocker for claiming better large-repo reliability in
  this repo's docs.
