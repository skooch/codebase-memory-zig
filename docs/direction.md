# Direction: Codebase Context Strategy Assessment

Date: 2026-04-14

## Purpose

This document captures an internal assessment of whether the knowledge graph + MCP + Cypher approach is the right architecture for reducing agent token costs, what the competitive landscape actually does, and whether there's an unexplored opportunity in designing for human-LLM collaboration patterns rather than purely optimizing LLM context retrieval.

---

## Part 1: Token Economics of the Current Approach

### The thesis

Pre-index a codebase into a knowledge graph, expose it via MCP tools, and agents save tokens by querying structured data instead of reading raw files.

### Where the savings come from

Reading a 500-line file costs ~750 tokens. A `search_graph` response for one symbol costs ~50-80 tokens. A `trace_call_path` across 5 files costs ~200 tokens vs ~3,750 to read all 5 files. On first read, that looks like a 10-20x win.

### Where the savings erode

**Prompt caching compresses repeat reads.** Anthropic's prompt caching gives ~90% cost reduction on cache hits (5-minute TTL). After the first file read, subsequent references within the same session are nearly free. The graph query costs the same every time. After the cache is warm, the graph offers no advantage for re-accessed files.

**MCP tool schema overhead is a per-turn recurring tax.** Each MCP server's tool definitions cost 1,500-8,000 tokens per turn. They are NOT prompt-cached -- they are re-sent with every API call. The codebase-memory surface advertises 13 tools with parameter schemas, likely costing 3,000-5,000 tokens of tool definition overhead on every single turn, whether the agent uses the tools or not. Over a 50-turn session, that's 150-250K tokens in tool definitions alone -- tokens that buy zero work.

**The agent usually still needs to read the file.** For the tasks agents actually do -- understanding code, modifying code, debugging -- the graph is insufficient. The graph says `validate CALLS checkInput`. It doesn't say how, why, what happens on failure, or what the surrounding control flow looks like. The agent reads the file anyway, making the graph query overhead.

**Query formulation is not free.** The agent spends tokens deciding what to query, formulating the MCP tool call, interpreting the structured result, and deciding whether to fall back to reading files. For simple lookups, this meta-reasoning overhead can exceed the cost of just grepping.

**Context degradation kicks in around 40% utilization.** Model performance drops when the context window fills past ~40%. On a 200K window, that's ~80K usable tokens. Fixed overhead (system prompt ~10K, tool schemas ~5-8K, workspace metadata up to 35K) can consume 50-60% of that budget before any work happens. Every MCP tool definition compounds this problem.

### GrepRAG vs GraphRAG: the published data says grep wins for code

The GrepRAG paper (arXiv 2601.23254) found that naive grep-based retrieval performs comparably to graph-based methods for code completion, and optimized grep with identifier re-ranking achieves state-of-the-art on CrossCodeEval and RepoEval benchmarks. Lexical precision at the edit site matters more than structural relationship traversal for the most common code tasks.

### The uncomfortable arithmetic

If the 13-tool MCP surface costs 3-5K tokens per turn in schema overhead, and a 50-turn session spends 150-250K tokens just in tool definitions, then the graph's query savings need to exceed that to break even. If graph queries save 30K tokens per session by avoiding some file reads, the net position may be negative.

---

## Part 2: What the Competitive Landscape Actually Does

Nobody else ships a Cypher-queryable knowledge graph via MCP.

### Embeddings-first: Cursor, GitHub Copilot

Cursor: AST-aware chunking, embeddings, Turbopuffer vector DB. Syncs every 3 minutes via Merkle trees. Retrieval is semantic similarity -- "find code about the same thing as what I'm working on."

Copilot: k-nearest neighbor embeddings trained via contrastive learning (Matryoshka Representation Learning). Combines open files, imports, and references for context.

Strength: handles fuzzy natural-language queries ("find the authentication logic") without the human knowing function names. Weakness: no structural awareness. Can't answer "what calls this" or "what breaks if I change this."

### Repo map: Aider

Tree-sitter symbol extraction, dependency graph, PageRank ranking, text summary within a token budget (default 1K tokens). Regenerated dynamically per turn. Uses 4.3-6.5% of context window vs 54-70% for search-heavy agents. Hit SWE-bench SOTA with this approach.

Strength: extremely cheap, no persistence layer, always fresh. Weakness: lossy -- tells you `validate()` exists and calls `checkInput()`, not what they do.

### On-demand reading: Claude Code

No indexing. CLAUDE.md for persistent instructions. Read/Grep/Glob tools for dynamic file access. Context compaction when the window fills. The model decides what to read based on the conversation.

Strength: always correct, no stale data, zero infrastructure. Weakness: cold starts are expensive, compaction loses context.

### Behavioral tracking: Windsurf

Tracks edits, terminal commands, clipboard, conversation history in real time. Infers intent from what the human is doing. "Fast Context" subagent retrieves at 2,800 tokens/sec. Auto-generates cross-session memory.

Strength: context is relevant to what the human is actually doing right now, not what the graph says is structurally related.

### Pre-indexed wikis: Devin

Indexes repos every few hours into persistent wikis with architecture diagrams, searchable summaries, citations. Sessions start by scanning the wiki for task-relevant context.

Strength: fast cold starts, human-readable artifacts. The wiki is useful to the human too, not just the LLM.

### Formalized compression: SWE-agent (Cat)

"Context as a Tool" paradigm. Treats context management as a first-class agent decision. Structured workspace with stable task semantics, condensed long-term memory, and high-fidelity short-term interactions. Compression is a callable action, not a passive heuristic.

### Where codebase-memory sits

It does something nobody else does: a persistent structural graph with a query language. The closest analogues are Devin's pre-indexed wiki (but Devin stores summaries, not queryable typed edges) and Aider's repo map (but Aider's is ephemeral and text-based).

What codebase-memory offers that others don't:
- Multi-hop structural queries (impact analysis, transitive dependencies)
- Persistent typed relationships (CALLS, WRITES, INHERITS) across sessions
- Change coupling from git history

What others offer that codebase-memory doesn't:
- Semantic retrieval (Cursor/Copilot embeddings)
- Behavioral context (Windsurf intent tracking)
- Token-budget-aware context selection (Aider PageRank within budget)
- Human-readable artifacts (Devin wiki)

---

## Part 3: The Human-Behavior Opportunity

### The tools are designed for the LLM. The human is the actual bottleneck.

Every approach above optimizes for the same thing: getting the right context into the LLM's prompt so it generates better code. The human is treated as a requester and reviewer, not as a participant with their own cognitive constraints.

### How humans actually use coding LLMs

**Short, interrupted sessions.** A developer works for 20 minutes, gets pulled into a meeting, comes back 2 hours later, works for 10 minutes, switches repos. The prompt cache is cold. The conversation is compacted. They have to re-orient. What helps isn't a graph query. It's: "You were adding WRITES edge extraction. You'd finished the extractor changes and were about to test the fixture." That's session continuity -- work-state memory, not code structure.

**Review is the bottleneck, not generation.** When the LLM writes 200 lines, the human reviews all of it. Time cost is proportional to diff size and inversely proportional to how well the human understands the context. Tools that help the human review faster -- showing what changed, what it affects, why each choice was made -- may be more valuable than tools that help the LLM generate faster. Impact analysis from a knowledge graph could serve this, but the current design surfaces it to the LLM via MCP, not to the human.

**The human needs their own mental model.** If the LLM navigates the codebase entirely through graph queries, the human doesn't build a mental map. When the tool is wrong (stale graph, missed edge, incorrect resolution), the human has no independent basis to catch the error. Tools that show the human the codebase structure -- not just feed it to the LLM -- support better collaboration. Devin's wiki does this. Aider's repo map is visible in the conversation. A knowledge graph queried silently by the LLM is opaque to the human.

**Intent preservation matters more than code structure.** The human's most common re-orientation question isn't "what does function X call?" -- they can grep for that. It's "what was I trying to do, and where did I get to?" This is task state, not code state. Windsurf's behavioral tracking gets at this.

**Humans alternate between directing and delegating.** Sometimes: "implement the WRITES edge extraction following the same pattern as USAGE" -- the human knows what they want, the LLM is a fast typist. Sometimes: "this test is failing and I don't know why" -- the human is lost, the LLM investigates. The tools needed for these modes are different. A one-size-fits-all 13-tool MCP surface pays the overhead for both modes on every turn.

**Trust calibration is a real cost.** When the LLM says "I found 3 callers via the knowledge graph," the human either trusts it or verifies it. If they verify (grep, read the files), the graph query was pure overhead. If they trust it and it's wrong, they debug a phantom issue. Tools that provide confidence signals ("2 from indexed graph, 1 from live grep") help calibration. Pure graph queries are opaque about freshness and completeness.

---

## Part 4: Concrete Directions

### The opportunity isn't "better graph for the LLM." It's "better shared context for the human-LLM pair."

**A. Session continuity and work-state memory.** Not "what does the code look like" but "what were we doing, what's the plan, what's done, what's next." CLAUDE.md, plans, and task lists partially address this. A purpose-built work-state memory -- tracking intent, decisions, progress, and blockers across sessions and compactions -- might be more valuable than a code graph.

**B. Human-visible codebase orientation.** Something like Aider's repo map or Devin's wiki, surfaced to the human as a persistent, browsable artifact. Not fed to the LLM silently. The human sees the same structural picture the LLM sees, can catch errors, and builds their own mental model.

**C. Review-oriented tooling.** Impact analysis surfaced to the human at review time: "this PR touches these callers, these tests should cover it, here's what might break." The graph can power this, but the consumer should be the human reviewer, not just the LLM generator.

**D. Adaptive tool surface.** Instead of 13 tools always present (paying schema overhead on every turn), a minimal default set that expands when the task needs it. Simple task: Read + Grep. Architecture review: add graph tools. Impact analysis: add traversal tools. The human or agent selects the toolset based on work mode.

**E. Behavioral context.** Track what files the human has open, what they recently edited, what tests they ran. Use this to bias context retrieval toward what's relevant to the human's current activity, not just what's structurally related in the graph.

---

## Part 5: Research Recommendations

| Direction | What to study | Why |
|-----------|---------------|-----|
| Repo map baseline | Build an Aider-style repo map from the existing tree-sitter infra and benchmark against the full graph on real tasks | Determines whether the graph adds value over a much simpler approach |
| Human review acceleration | Prototype impact-analysis output surfaced to the human at commit/PR time, not just to the LLM via MCP | Tests whether the graph's best value is as a human tool, not an LLM tool |
| Adaptive tool loading | Measure per-turn schema overhead with 13 tools vs 3 tools + on-demand expansion | Quantifies the token cost of the current approach |
| Work-state memory | Compare session re-orientation time with current CLAUDE.md+plans vs a purpose-built task-state memory | Tests the hypothesis that intent memory matters more than code memory |
| Behavioral context | Log what files the user has open/recently edited and use that to bias retrieval; compare against graph-only retrieval | Tests the Windsurf hypothesis with existing infrastructure |
| Net token measurement | Instrument real sessions to measure tokens spent on tool schemas vs tokens saved by graph queries | Answers the fundamental question of whether the current approach is net-positive |

---

## Part 6: What This Means for the Graph

The tree-sitter parsing, symbol extraction, and relationship tracking are real assets. The question is whether those assets are best exposed as 13 MCP tools for the LLM, or as infrastructure that serves both the human and the LLM in ways that match how the pair actually works together.

The graph's strongest unique value -- multi-hop impact analysis, change coupling, architectural overview -- is occasional, not per-turn. Paying the per-turn schema overhead for occasional value is a poor trade. The graph's value might be better realized as:

- A human-facing dashboard or wiki (like Devin)
- A repo-map generator (like Aider) with optional deep queries
- A review-time impact analyzer (surfaced at commit/PR, not every turn)
- A cold-start orientation tool (used once per session, not per turn)

None of these require 13 MCP tools present on every turn.

---

## Sources

- GrepRAG: arXiv 2601.23254 -- grep + ranking beats graph retrieval for code tasks
- Aider repo map: aider.chat/docs/repomap.html, aider.chat/2023/10/22/repomap.html
- MCP token overhead: mindstudio.ai/blog/claude-code-mcp-server-token-overhead
- TU Wien thesis on agent token usage: repositum.tuwien.at (Hrubec, 2025)
- Context as a Tool (SWE-agent Cat): arXiv 2512.22087
- Cursor indexing: read.engineerscodex.com, cursor.com/blog/secure-codebase-indexing
- Copilot context: code.visualstudio.com/docs/copilot, infoq.com/news/2025/10/github-embedding-model
- Windsurf Cascade: docs.codeium.com/windsurf/cascade
- Sourcegraph Cody: sourcegraph.com/blog/how-cody-provides-remote-repository-context, arXiv 2408.05344
- Devin indexing: docs.devin.ai/onboard-devin/index-repo
- Anthropic prompt caching: docs.anthropic.com
