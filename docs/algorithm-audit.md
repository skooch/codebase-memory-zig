# Algorithm & Pattern Audit

Audit of every algorithm and architectural pattern in codebase-memory, assessed for complexity fit in the Zig port.

Verdicts: **RIGHT** (keep), **OVER** (simplify), **UNDER** (strengthen), **RETHINK** (wrong approach)

---

## Scoreboard

| Verdict | Count | Items |
|---------|-------|-------|
| RIGHT | 35 | Core is sound |
| OVER | 10 | #3 slab, #7 Louvain, #16 AC, #29 page writer, #41 RSS budget, #42 mimalloc, #44 opaque handles, #45 visitor, #50 camelCase split, #51 config normalization |
| UNDER | 1 | #36 hop-based risk |
| RETHINK | 2 | #13 Cypher parser, #14 expression tree |

---

## Data Structures

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 1 | Robin Hood hashing | RIGHT | Standard open-addressing. Bounded probe distance, no tombstones, simple in Zig. |
| 2 | Arena allocator | RIGHT | Textbook fit for per-file extraction. Maps to `std.heap.ArenaAllocator`. |
| 3 | Slab allocator | OVER | Redundant with Zig's `MemoryPool(T)` or GPA. Drop custom slab. |
| 4 | String interning | RIGHT | Labels repeat millions of times. Saves memory, enables pointer equality. |
| 5 | Dynamic array (2x growth) | RIGHT | `std.ArrayList` for free. |

## Graph & Search

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 6 | BFS traversal | RIGHT | Correct for N-hop call/caller tracing. Hop counts are small (3). |
| 7 | Louvain community detection | OVER | Research-grade for a "group files into components" problem. **Instead:** label propagation or directory-based grouping with edge cross-refs. |
| 8 | MinHash (K=64) | RIGHT | Standard code similarity approach. 256 bytes/function, sufficient accuracy. |
| 9 | LSH (32 bands x 2 rows) | RIGHT | Avoids O(n^2) pairwise comparison. Complexity contained in one file. |
| 10 | Property graph in SQLite | RIGHT | Natural model, right engine for local dev tool. Core decision, correct. |

## Parsing & Language Analysis

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 11 | Tree-sitter | RIGHT | Industry standard. No alternative for 66 languages. |
| 12 | Single-pass tree cursor walk | RIGHT | 1 walk instead of 7. Dispatch table keeps it clean. Matters for throughput. |
| 13 | Hand-written Cypher parser | RETHINK | 3,400 lines for a subset AI agents barely use. **Instead:** Cypher pattern → SQL template table with lightweight tokenizer. Covers 95% of usage. |
| 14 | Expression tree for WHERE | RETHINK | Part of Cypher over-engineering. WHERE clauses are simple property filters. **Instead:** compile predicates directly to SQL. |
| 15 | Scope stack | RIGHT | Natural way to track enclosing function/class during AST walk. |
| 16 | Aho-Corasick | OVER | Not actually implemented — infrascan uses `strcmp`/`strstr`. Dozens of patterns don't need AC. **Don't add it.** |
| 17 | Regex-to-LIKE pre-filtering | RIGHT | Smart optimization. SQLite uses indexes on LIKE prefixes. Low complexity, high payoff. |
| 18 | Glob-to-LIKE conversion | RIGHT | Same rationale. Minimal code, meaningful speedup. |

## Call Resolution

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 19 | 5-strategy resolution chain | RIGHT | Import map → same module → same package → import-reachable → fuzzy. Heart of the tool's value. |
| 20 | Multimap (name → [QNs]) | RIGHT | Functions share bare names across modules. Necessary. |
| 21 | Fuzzy bare-name matching | RIGHT | Low-confidence fallback (0.30-0.40) better than nothing. Agents filter on threshold. |
| 22 | Go implicit interface satisfaction | RIGHT | Essential for Go's structural typing. Language-specific but necessary. |

## Pipeline & Concurrency

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 23 | 7-phase pipeline | RIGHT | Phases have genuine data dependencies. Ordering dictated by the problem. |
| 24 | Work-stealing thread pool | RIGHT | Just an atomic counter + `fetch_add`. Lightest possible parallel dispatch. |
| 25 | Per-worker graph buffer + merge | RIGHT | Standard contention-avoidance. Alternative is locking the hot path. |
| 26 | Result caching across phases | RIGHT | Parse each file once, reuse 3x. Genuine optimization. |
| 27 | Fused parallelism (git history) | RIGHT | I/O-bound git log concurrent with CPU-bound extraction. Free parallelism. |
| 28 | Global index lock | RIGHT | Atomic int, simplest possible. Non-blocking try for watcher. |

## Indexing & Storage

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 29 | Direct SQLite page writer | OVER | 1,875 lines of manual B-tree page construction. Any schema change breaks it. **Instead:** bulk INSERT with `journal_mode=OFF`, disabled sync, prepared statements, large transactions. 100K+ rows/sec is enough. |
| 30 | WAL journal mode | RIGHT | One-line PRAGMA, universally recommended. |
| 31 | Incremental indexing (mtime+size+SHA256) | RIGHT | Fast pre-filter plus content hash for correctness. |
| 32 | Upsert with UNIQUE constraint | RIGHT | SQLite handles natively via `ON CONFLICT REPLACE`. |
| 33 | Adaptive polling | RIGHT | Scales with project size. Simple formula, sensible caps. |
| 34 | Git HEAD polling | RIGHT | More reliable than fsnotify across platforms. Catches committed + uncommitted. |

## Change Coupling & Impact

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 35 | Co-change coupling from git log | RIGHT | Hidden dependencies static analysis can't find. Bounded by history depth. |
| 36 | Hop-based risk classification | UNDER | BFS depth alone is crude. 2 hops via logger != 2 hops via data dep. **Instead:** weight by edge type (CALLS > IMPORTS > SIMILAR_TO). Composite score, not just hops. |
| 37 | Impact summary aggregation | RIGHT | Reasonable summary for agent consumption. |

## Serialization & Protocol

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 38 | JSON-RPC 2.0 over stdio | RIGHT | MCP spec requirement. |
| 39 | Manual JSON (yyjson in C) | RIGHT | Correct for C. Fastest JSON lib, allocation-free writes. |
| 40 | Comptime struct reflection (Zig) | RIGHT | Eliminates hundreds of lines of manual JSON. Biggest win of the port. |

## Memory Management

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 41 | RSS-based memory budgeting | OVER | Peak memory is bounded for <100K file codebases. **Instead:** fixed caps, fail with clear error on truly enormous repos. |
| 42 | mimalloc global override | OVER | Zig's GPA is already modern + thread-safe with safety features. Overriding sacrifices safety for marginal throughput. **Instead:** DebugAllocator in debug, `c_allocator` in release. |
| 43 | Explicit allocator passing | RIGHT | Idiomatic Zig. The language's design, not a choice. |

## Platform & Compatibility

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 44 | Opaque handle pattern | OVER | Replaced by Zig's `pub`/non-`pub`. Don't port; use natural encapsulation. |
| 45 | Visitor pattern (callback + void*) | OVER | In Zig, becomes iterator (`next()`) or closure. Don't port; use Zig iterators. |
| 46 | Function pointer dispatch for passes | RIGHT | Clean in both languages. Slice of `fn` pointers or tagged unions in Zig. |
| 47 | Tagged union for enums | RIGHT | Zig's natural exhaustive switch dispatch. |
| 48 | StaticStringMap (comptime perfect hash) | RIGHT | Zero cost, zero alloc, O(1) for ~100 extensions. |

## Qualified Name Computation

| # | Item | Verdict | Notes |
|---|------|---------|-------|
| 49 | Path-based FQN | RIGHT | Globally unique, deterministic, handles edge cases. |
| 50 | CamelCase splitting | OVER | Speculative. AI agents pass keys as-is. **Instead:** `COLLATE NOCASE` at query time. |
| 51 | Config key normalization | OVER | Normalizing creates impedance mismatch. **Instead:** store original, add normalized form only if explicitly requested. |

---

## Action Items for Zig Port

**Drop entirely:**
- Slab allocator (#3) — use `MemoryPool(T)` or GPA
- Direct SQLite page writer (#29) — use bulk INSERT
- RSS-based memory budgeting (#41) — use fixed caps
- mimalloc override (#42) — use Zig stdlib allocators
- CamelCase splitting (#50) and config normalization (#51)
- Aho-Corasick (#16) — was never actually implemented

**Simplify:**
- Louvain (#7) → label propagation or directory-based clustering
- Cypher engine (#13, #14) → pattern-matching Cypher-to-SQL translator

**Strengthen:**
- Risk classification (#36) → add edge-type weighting to composite score

**Replaced by Zig idioms (no action needed):**
- Opaque handles (#44) → `pub`/non-`pub`
- Visitor pattern (#45) → iterators
- Manual JSON (#39) → comptime struct reflection (#40)
