# Plan: Near-Parity Full-Parity Promotion Program

## Goal
Replace the current over-broad near-parity draft with an executable program of
smaller parity-promotion plans.

This program plan does not try to implement every near-parity row itself. Its
job is to:

1. define the parity rubric for promotion vs downgrade
2. split the work into independent todo plans
3. queue those plans in execution order

## Current Phase
In progress

## File Map
- Modify: `docs/plans/new/13-near-parity-promotion-program-plan.md`
- Modify: `docs/plans/new/README.md`
- Create: `docs/plans/implemented/14-protocol-tool-surface-full-parity-plan.md`
- Create: `docs/plans/implemented/15-query-analysis-full-parity-plan.md`
- Create: `docs/plans/new/16-graph-exactness-full-parity-plan.md`
- Create: `docs/plans/new/17-runtime-cli-packaging-full-parity-plan.md`

## Systemic-Fix Review

### Problem
The original draft was not a practical todo plan. It bundled protocol,
query-contract, graph-model, runtime, CLI, packaging, and documentation work
into one file, while also carrying unresolved policy choices that materially
change the target.

### Facts
- The draft touched independent subsystems: protocol surface, query and
  analysis tools, graph and pipeline rows, and runtime or CLI packaging rows.
- Several rows require a product decision before implementation:
  `ingest_traces` tool-list parity, `moderate` mode promotion, `Channel` /
  `LISTENS_ON` vocabulary parity, and packaging parity scope.
- Some rows are likely promotable with stronger tests only, while others need
  real code changes or should be downgraded to `Partial`.

### Root Cause
The draft treated a parity program as if it were one implementation slice.
That makes completion ambiguous and encourages touching many files before any
single row can be promoted honestly.

### Alternatives Considered
- Keep one mega-plan and add more detail.
  Rejected: still mixes unrelated subsystems and leaves completion undefined.
- Rewrite into one execution slice and defer the rest informally.
  Rejected: loses the full inventory and hides the remaining queue.
- Split into independent todo plans under one ordering plan.
  Selected: smallest intervention that makes the work executable and auditable.

### Selected Fix
Create one program plan plus four subsystem todo plans:
- protocol and tool-surface exactness
- query and analysis contract exactness
- graph and pipeline exactness
- runtime, CLI, and packaging exactness

## Parity Rubric

A row can move from `Near parity` to `Full parity` only if both are true:
- the known behavioral delta is closed or proven nonexistent
- the verification surface is strong enough to catch regression on that row

A row must be downgraded to `Partial` if either is true:
- the remaining delta is deliberate and still user-visible
- the row depends on bounded fixtures where exact contract parity is the claim

## Plan Inventory

### Plan 1: protocol and tool surface
- Rows: `initialize`, `tools/list`, `tools/call`, one-shot CLI tool execution,
  CLI progress output, `index_repository`
- Main question: exact protocol and public schema parity vs compatibility with
  the original stub-only `ingest_traces`

### Plan 2: query and analysis contracts
- Rows: `query_graph`, `trace_call_path`, `get_code_snippet`,
  `get_graph_schema`, `get_architecture`, `search_code`, `list_projects`,
  `delete_project`, `index_status`, `manage_adr`
- Main question: where exact response-shape fixtures are needed before
  promotion

### Plan 3: graph and pipeline exactness
- Rows: structure pass, call-resolution, usage/type edges, semantic edges,
  registry/FQN, incremental, parallel, `SIMILAR_TO`, `TESTS`,
  `CONFIGURES`, `FILE_CHANGES_WITH`, `USES_TYPE`, `THROWS`/`RAISES`,
  route-linked `DATA_FLOWS`
- Main question: which rows need new graph fixtures only, and which rows need
  real model changes before they can ever be promoted

### Plan 4: runtime, CLI, and packaging exactness
- Rows: runtime cache/DB, watcher and auto-index lifecycle, startup update
  notice, install/uninstall/update/config, agent detection/config support,
  setup scripts, packaging, ops scripts
- Main question: which rows are promotable with exact harness coverage vs which
  should be downgraded because the upstream surface is intentionally broader

## Phases

### Phase 1: Define the execution split
- [x] Keep this file scoped to program-level ordering and promotion rules only.
- [x] Create the four subsystem todo plans in `docs/plans/new/`.
- [x] Ensure each subsystem plan has an exact file map, concrete verification
      commands, and explicit downgrade criteria where needed.
- **Status:** completed

### Phase 2: Order the queue
- [x] Put protocol/tool-surface first because it defines the public parity
      contract and harness shape.
- [x] Put query/analysis second because it depends on the protocol and fixture
      posture but not on packaging decisions.
- [x] Put graph exactness third because some rows may be downgraded depending
      on model-vocabulary decisions discovered earlier.
- [x] Put runtime/CLI/packaging fourth because several rows likely need
      reclassification, not implementation.
- **Status:** completed

### Phase 3: Exit criteria for the program
- [ ] Mark this program plan complete only when each subsystem plan has been
      either completed or explicitly abandoned with a downgrade decision.
- [ ] Require `docs/port-comparison.md`, `docs/gap-analysis.md`, and
      `docs/interop-testing-review.md` to reflect the measured final state.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Split the work into four subsystem plans | The original draft spans independent subsystems and cannot be executed safely as one todo plan. |
| Keep promotion and downgrade in the same program | Honest parity requires both promotion where earned and downgrade where the gap is real. |
| Sequence protocol first | Later plans depend on a stable public contract and harness posture. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
