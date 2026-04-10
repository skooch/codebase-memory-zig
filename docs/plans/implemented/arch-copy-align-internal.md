# Plan: Adopt Conventions From align-internal Into codebase-memory-zig

## Status
Implemented on 2026-04-11. This plan is complete and now lives in `docs/plans/implemented/`.

## Goal
Adopt the source repo's useful Zig-project conventions into the target repo without overwriting stronger target-specific choices, importing source-product packaging, or blurring the target repo's current plan and agent-doc structure.

## Repos
- Source: `/Users/skooch/projects/align-internal`
- Target: `/Users/skooch/projects/codebase-memory-zig`

## Summary
- Overall fit: `medium-high`
- Recommendation: `apply selected items after decisions`

## File Map
- Modify: `docs/plans/implemented/arch-copy-align-internal.md`
- Add if approved: `.github/workflows/ci.yml`
- Add if approved: `README.md`
- Add if approved: `zlint.json`
- Modify if approved: `mise.toml`
- Modify if approved: `build.zig.zon`
- Modify if approved: `CLAUDE.md`

## Inventory
| Convention | Source evidence | Target evidence | Classification | Notes |
|---|---|---|---|---|
| Zig version policy | `mise.toml`, `build.zig.zon`, `.claude/README.md` | `mise.toml`, `build.zig.zon`, `CLAUDE.md` | `ask` | Source is internally inconsistent: `mise.toml` says `latest`, while build and docs say `0.15.2`. Target is consistently pinned to `0.15.1`. |
| CI workflow | `.github/workflows/ci.yml` | no `.github/workflows/` present | `translate` | Source CI shape is useful, but commands must be translated to target build/test commands and current portability constraints. |
| Extra linting | `.github/workflows/ci.yml`, `zlint.json` | no lint config or extra lint tool | `ask` | Adopting `zlint` adds a new external dependency and the source currently downloads the latest binary ad hoc in CI. |
| Cross-compile verification | `.github/workflows/ci.yml`, `README.md`, `.claude/README.md` | `CLAUDE.md` cross-compile note only | `translate` | Source's cross-target smoke coverage is useful, but target should likely start with a narrower matrix than the source's full release set. |
| Release automation and changelog | `.github/workflows/release.yml`, `cliff.toml`, `CHANGELOG.md`, `CONTRIBUTING.md` | no release workflow, no changelog automation | `ask` | This changes release policy, tag semantics, and commit expectations rather than just tooling. |
| GitHub Action packaging | `action.yml`, `problem-matcher.json`, `README.md` action section | no action packaging files | `skip` | Source ships a GitHub Action product; target is an MCP server and should not inherit that distribution model by default. |
| Human onboarding docs | `README.md`, `CONTRIBUTING.md`, `docs/Home.md` | `CLAUDE.md`, technical docs under `docs/` | `translate` | Target lacks a human-facing root README and contributor guide; source provides a good shape that needs target-specific content. |
| Agent-doc and plan layout | `.claude/README.md`, `.claude/plans/` | `CLAUDE.md`, `.agents/skills/`, `docs/plans/*` | `keep` | Target already has a stronger, more current agent-facing and planning structure and should keep it. |
| Claude permission settings | `.claude/settings.json` | `.claude/settings.json` | `keep` | Both repos already carry local Claude settings; source additions are not necessary for the target migration. |

## Proposed Changes
- Bundle 1: translate the source CI shape into a target-specific GitHub Actions workflow that runs `zig fmt --check`, `zig build`, `zig build test`, and a verified `zlint` invocation over the repo's Zig files.
- Bundle 2: translate the source's human-facing repo docs into a target `README.md` that explains build, test, run, architecture, and verification commands without replacing the existing `CLAUDE.md`.
- Bundle 3: raise the target's Zig floor from `0.15.1` to `0.15.2` in repo-managed toolchain pins and guidance.

## Keep In Target
- Keep the target's existing `CLAUDE.md` as the primary agent-facing entrypoint.
- Keep the target's `docs/plans/{new,in-progress,implemented,paused}` convention rather than adopting the source's `.claude/plans/` layout.
- Keep the target's current avoidance of source-product packaging such as `action.yml` and GitHub problem matcher files.

## Skip From Source
- Skip `action.yml` and `problem-matcher.json` because they package and annotate the source repo's GitHub Action product rather than the target MCP server.
- Skip blindly copying the source release artifact names and platform matrix because `align` distribution names do not map directly to `cbm`.
- Skip the source `.claude/README.md` layout because the target already has a stronger top-level `CLAUDE.md` plus `.agents/skills/`.
- Skip copying `mise.toml` verbatim because the source's `latest` Zig setting conflicts with its own `0.15.2` documentation and would weaken target reproducibility.

## Open Decisions
| Order | Decision | Options | Recommended choice | Why it matters |
|---|---|---|---|---|
| 1 | Should the target keep Zig `0.15.1` or move toward the source's `0.15.2` baseline? | `keep 0.15.1`, `raise to 0.15.2 now`, `defer until separate upgrade task` | `defer until separate upgrade task` | Version policy touches local setup, CI, dependency compatibility, and any future release matrix. |
| 2 | How broad should the translated CI bundle be? | `fmt+build+test only`, `fmt+build+test plus one cross-compile smoke`, `full source-style cross-platform matrix` | `fmt+build+test plus one cross-compile smoke` | This sets the reliability/cost balance for the first CI workflow. |
| 3 | Should the target adopt `zlint` or stay with formatter-only checks for now? | `no extra linter`, `add zlint in CI only`, `add zlint for local and CI workflows` | `no extra linter` | This adds external tool maintenance and influences contributor setup friction. |
| 4 | Should this repo add release automation and changelog generation now? | `no release automation yet`, `add tagged release + changelog`, `add release + broader distribution work later` | `no release automation yet` | This changes commit expectations, versioning workflow, and whether the repo is ready to publish binaries. |
| 5 | How much human-facing repo documentation should be added in the first pass? | `README only`, `README plus CONTRIBUTING`, `README plus CONTRIBUTING plus roadmap/release docs` | `README plus CONTRIBUTING` | This determines whether the migration focuses on basic onboarding or a broader docs surface. |

## Apply Approval
Before implementation, ask whether to apply now and which commit mode to use:
- `commit-by-item`
- `commit-all`
- `no-commit`

Current target worktree note:
- `git status --short --branch` on `main` currently shows unrelated untracked files and directories, so any commit path needs careful staging instead of blanket adds.

## Decision Walkthrough
After the user chooses a commit mode, ask each open decision as its own step-by-step question in the order above.
- Question 1: Zig version policy for the target repo
- Question 2: desired CI breadth for the first translated workflow
- Question 3: whether to adopt `zlint`
- Question 4: whether to add release automation and changelog tooling
- Question 5: whether the docs bundle should stop at `README` or include `CONTRIBUTING`
- Stop and wait for an answer after each question.

## Decision Answers
- Question 1: raise the target repo from Zig `0.15.1` to `0.15.2` now.
- Question 2: use a narrower first CI workflow with `fmt+build+test` only.
- Question 3: add `zlint` for both local and CI workflows.
- Question 4: do not add release automation or changelog generation in this first pass.
- Question 5: add a root `README.md` only in this first pass.

## Completion Summary
- Added a target-specific GitHub Actions workflow at `.github/workflows/ci.yml` with `zig fmt --check`, `zig build`, `zig build test`, and a working `zlint` step.
- Added a root `README.md` with human-facing build, run, lint, and repo-layout guidance.
- Added `zlint.json` and updated repo guidance to use `find src -name '*.zig' | zlint -S`.
- Raised the repo-managed Zig floor to `0.15.2` in `mise.toml`, `build.zig.zon`, and `CLAUDE.md`.
- Left release automation, changelog scaffolding, and source-product GitHub Action packaging out of scope for this migration.

## Verification Results
- `zig build`
- `zig fmt --check src/ build.zig`
- `zig build test`
- `find src -name '*.zig' | zlint -S`
- Reviewed `.github/workflows/ci.yml` to confirm every referenced command exists in the repo.
- Verified `README.md` commands and file paths against the current repository.

## Verification
- `zig build`
- `zig build test`
- `zig fmt --check src/ build.zig` or the repo's chosen equivalent formatting check
- If CI is added, validate the workflow YAML and confirm each referenced command exists in the repo
- If docs are added, verify every command and file path in `README.md`
- If release automation is added, dry-run the changelog generation inputs and verify artifact names are target-specific

## Residual Risks
- The target worktree is already dirty with unrelated untracked files, which raises accidental-staging risk if apply work begins without disciplined staging.
- The source repo's Zig version guidance is not internally consistent, so toolchain settings must be chosen deliberately rather than copied.
- The source release workflow assumes a public binary-release model that the target may not want yet.
- The local interoperability harness in `scripts/run_interop_alignment.sh` is useful for manual validation, but it depends on sibling-repo layout and should not be assumed to be a default CI gate.
