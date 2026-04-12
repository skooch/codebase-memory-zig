# Plan: Operational Controls and Configurability Feature Cluster

## Goal
Expose the operational knobs that upstream users repeatedly asked for around install scope, cache location, host binding, progress visibility, hook behavior, and first-run ergonomics, while keeping the Zig port’s current contract simpler than the original by default.

## Research Basis

Upstream requests and friction points captured in this plan:
- Installer and config-scope control: `#145`, `#154`
- Runtime and hook behavior control: `#188`, `#214`, `#229`
- Smaller operational correctness details that affect trust: `#54`

Upstream PRs that show the likely implementation shape:
- Configurable extension mapping: `#60`, `#73`
- User-facing telemetry and ergonomics: `#61`, `#108`
- Installer scope and config portability: `#63`, `#64`, `#74`
- Operational helper hooks and triggers: `#132`, `#156`
- Cache directory and update-flow polish: `#172`, `#173`
- Query-shape ergonomics adjacent to operational defaults: `#181`, `#231`

Observed upstream pattern:
- Users wanted more control over where data lives and when automation fires, but the healthier fixes usually made the defaults explicit rather than adding silent magic.
- Many support issues would have been easier if the product clearly separated configuration knobs, runtime status output, and agent-specific side effects.

## Current Phase
Phase 1

## File Map
- Modify: `docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-plan.md`
- Create: `docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-progress.md`
- Modify: `docs/gap-analysis.md`
- Modify: `docs/port-comparison.md`
- Modify: `docs/zig-port-plan.md`
- Modify: `src/cli.zig`
- Modify: `src/main.zig`
- Modify: `src/mcp.zig`
- Modify: `src/runtime_lifecycle.zig`
- Modify: `src/discover.zig`
- Modify: `scripts/run_cli_parity.sh`
- Create: `docs/configuration-matrix.md`
- Create: `testdata/interop/configuration/env-overrides/README.md`

## Phases

### Phase 1: Inventory the Control Surface
- [ ] Capture every requested operational knob in `docs/gap-analysis.md`, separating installer scope, cache and path config, runtime trigger behavior, host binding, and query-default ergonomics.
- [ ] Add a configuration fixture area under `testdata/interop/configuration/` so env-var and config-file behavior can be tested without touching a real home directory.
- [ ] Record the exact CLI, config, and runtime verification commands in `docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-progress.md`.
- **Status:** pending

### Phase 2: Make the Knobs Explicit
- [ ] Extend `src/cli.zig`, `src/main.zig`, `src/mcp.zig`, `src/runtime_lifecycle.zig`, and `src/discover.zig` so cache location, host binding, auto-index triggers, progress output, hook behavior, and extension mappings are controlled by explicit config or env surfaces instead of hidden defaults.
- [ ] Add `docs/configuration-matrix.md` to document each supported knob, its default, its scope, and its verification path.
- [ ] Update `scripts/run_cli_parity.sh` so the operational surfaces are exercised in temp-home fixtures rather than relying on developer machine state.
- **Status:** pending

### Phase 3: Verify and Reclassify
- [ ] Run `zig build`, `zig build test`, and `bash scripts/run_cli_parity.sh` with the new config fixtures until behavior is stable and reversible.
- [ ] Update `docs/port-comparison.md` only where the Zig port now deliberately matches or intentionally diverges from the original operational controls.
- [ ] Record remaining deferred knobs and rejected complexity in `docs/plans/new/improvements/operational-controls-and-configurability-feature-cluster-progress.md`.
- **Status:** pending

## Decisions
| Decision | Rationale |
|----------|-----------|
| Prefer explicit config and env controls over implicit automation | The upstream issues around hooks and installer side effects show that surprising behavior is expensive to support. |
| Keep operational controls separate from client-matrix expansion | A smaller, well-documented control surface is easier to verify than a wider but implicit one. |

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
