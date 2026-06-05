# Sprint 31 — onboarding clarity + phase-runner that really runs (v2.19.0)

> ✅ **COMPLETE** — shipped v2.19.0 (2026-06-06). All four workstreams
> (A rename, B breadcrumbs, C consensus-run.sh + aggregator `--finalize`,
> D docs/version/sprint-31.sh) landed; `sprint-31.sh` is 41/41 and the
> consensus suites (14/15/16/17/19/23/28/30) stay green.

## Context

A new operator started a project from a PRD and hit two real problems, both confirmed in code:

1. **`init` name collision.** `skills/init/` is named `init`, colliding with Claude Code's built-in `/init`. Typing "init" fuzzy-matches VibeFlow's. (It's already `disable-model-invocation: true`, so it never *auto*-runs — the only issue is the name.)
2. **"What do I run next?" is unanswered, and `phase-runner` deadlocks.** After `prd-quality-analyzer`, nothing tells the operator the next command. They guessed `phase-runner`, which then **structurally cannot complete**: its Step 3 says *"invoke consensus-orchestrator via slash command"* but the whole consensus chain (`consensus-orchestrator/specialist/arbiter/apply/advance`) is `disable-model-invocation: true` — the model literally cannot fork them. Worse, Step 2's analyzer writes `consensus-needed.json`, which trips `consensus-gate.sh` and blocks every subsequent `Bash/Write/Edit` — including phase-runner's own next step. Net result: the painful "BLOCKED" session the operator pasted.

Root contradiction: Sprint 14-16 made consensus **operator-gated** (un-forkable + gate hook), while Sprint 19 promised phase-runner is a **one-command autonomous walk**. Both can't be true.

**Intended outcome** (operator chose "both together" + rename to `onboard`):
- Rename `init` → `onboard` to kill the collision.
- Add an explicit **breadcrumb** (`▶ Next: …`) to every phase-flow skill so the next command is always visible.
- Make phase-runner **genuinely run** the consensus verdict itself (extract the codex/gemini/aggregator pipeline into a shared script it can call as plain Bash), auto-advance on APPROVED — and on NEEDS_REVISION stop with an honest breadcrumb instead of deadlocking. The deep-rewrite revision loop (specialist/arbiter/apply) stays operator-gated by design, because those rewrite the PRD/ADR and need a human.

This is a breaking command rename → **v2.19.0**, new `docs/SPRINT-31.md`.

---

## Workstream A — rename `init` → `onboard`

- Move `skills/init/` → `skills/onboard/`; set frontmatter `name: onboard`. Keep `disable-model-invocation: true`, keep the Phase Contract (REQUIREMENTS-only), keep `allowed-tools`.
- **No back-compat shim** — a lingering `init` skill would re-create the collision the operator wants gone.
- Update the skill registry in `skills/phase-policy.json` (and `hooks/scripts/phase-policy.json` if it lists skills) from `init` → `onboard`.
- Update **live** docs + CLAUDE.md "Key Commands" + every skill that tells the operator to run `/vibeflow:init` (phase-runner, advance, consensus-arbiter, learning-apply, repo-fingerprint, consensus-specialist, GETTING-STARTED.md, CONFIGURATION.md, TROUBLESHOOTING.md). **Leave historical records untouched** — `release-notes/*.md` and `docs/SPRINT-{4,12,13}.md` document what shipped then.
- Update `tests/integration/sprint-13.sh` sentinels: `INIT_MD` path → `skills/onboard/SKILL.md`, and the `for skill in init …` loop → `onboard`. Sweep other `tests/integration/*.sh` for `skills/init` / `vibeflow:init` references and repoint.

## Workstream B — breadcrumb (`▶ Next:`) footer convention

A uniform, copy-pasteable last line on every phase-flow skill so the operator never has to guess.

- `onboard` final step prints: `▶ Next: /vibeflow:prd-quality-analyzer <your-PRD-path>`.
- `prd-quality-analyzer` final step prints: `▶ Next: /vibeflow:phase-runner` (REQUIREMENTS converge+advance in one) **or** `/vibeflow:consensus-orchestrator <PRD>` (manual).
- Each analyzer / consensus step ends with the literal next command for its phase. Several skills already half-do this (`advance`, `phase-runner`, `consensus-specialist`) — standardize the exact `▶ Next:` prefix so it's greppable and testable.
- New integration sentinels assert the `▶ Next:` line exists in onboard + prd-quality-analyzer + phase-runner (REQUIREMENTS path).

## Workstream C — phase-runner that really runs consensus

The riskiest change. Extract, don't duplicate.

1. **New `hooks/scripts/consensus-run.sh <primaryArtifact>`** — lift the *already self-contained* bash from `skills/consensus-orchestrator/SKILL.md` (Step 3 region: `vf_run_timeout`, `build_review_prompt`, `build_memory_block`, `append_cli_verdict`, the codex + gemini invocations, then the `consensus-aggregator.sh` call). It writes the session jsonl + `verdict.json` + `history.jsonl` exactly as today, then **drains `consensus-needed.json`** on success. Single source of truth.
2. **Refactor `consensus-orchestrator/SKILL.md`** to call `consensus-run.sh` instead of carrying the inline bash, then keep its model-driven extras (the `claude-reviewer` subagent as a 3rd reviewer, arbiter auto-invoke). Operator path behavior preserved — regression-pin via existing sprint-14/15/17 assertions.
3. **`consensus-gate.sh`**: add `*consensus-run.sh*` to the command allowlist (alongside the existing `vibeflow:consensus-orchestrator` cases) so phase-runner's Bash call isn't blocked by the very marker it's about to drain.
4. **`phase-runner/SKILL.md`** Step 3: replace "invoke consensus-orchestrator via slash command" with a direct `bash consensus-run.sh <primary>` call; read `verdict.json`.
   - `APPROVED` → auto-advance via `mcp__sdlc-engine__sdlc_advance_phase` (already wired) → print `▶ Next: /vibeflow:phase-runner` for the new phase.
   - `NEEDS_REVISION` / `HUMAN_APPROVAL_REQUIRED` → **stop, no fabrication**, print the honest breadcrumb: `▶ Next: /vibeflow:consensus-specialist <sid>` → `/vibeflow:apply-arbiter-patch <sid> --yes` → re-run `/vibeflow:phase-runner`. (Specialist/arbiter/apply remain operator-gated deep rewrites — unchanged.)
   - `REJECTED (rejected≥1)` → stop, operator triage (unchanged).
   - Add `Bash(bash hooks/scripts/consensus-run.sh*)` to phase-runner `allowed-tools`.
   - Update the SKILL prose that currently claims it forks the disable-model-invocation chain — the description no longer lies.

This makes the **APPROVED path a true one-command walk** while keeping the human-judgment revision loop explicit and gated — resolving the deadlock without weakening the Sprint 16 guardrail.

## Workstream D — docs, version, sprint bookkeeping

- New `docs/SPRINT-31.md` (this plan, auto-saved).
- New `docs/ONBOARDING.md` (or extend `docs/GETTING-STARTED.md`): the canonical first-run sequence `onboard → prd-quality-analyzer → phase-runner`, and the breadcrumb convention.
- Refresh `docs/PHASE-BOUNDARIES.md` / phase-runner references where they name `init`.
- Bump plugin version → 2.19.0; add `CHANGELOG.md` + `release-notes/2.19.0.md` entries (rename = breaking command-name change, called out explicitly).
- New `tests/integration/sprint-31.sh` harness with `[S31-A]` rename completeness (no live `skills/init` / `vibeflow:init` refs outside historical docs), `[S31-B]` breadcrumb sentinels, `[S31-C]` consensus-run.sh exists + gate allowlists it + orchestrator calls it + phase-runner calls it on the verdict, `[S31-Z]` self-audit. Update the CLAUDE.md test-layer ledger + total.

---

## Verification

1. `bash hooks/tests/run.sh` — consensus-gate allowlist for `consensus-run.sh` + marker drain.
2. `cd mcp-servers/sdlc-engine && npm test` — unaffected, confirm green (no engine change expected).
3. `bash tests/integration/sprint-13.sh` — rename sentinels now point at `skills/onboard`.
4. `bash tests/integration/sprint-14.sh` + `sprint-15.sh` + `sprint-17.sh` — consensus-orchestrator refactor preserves the operator path.
5. `bash tests/integration/sprint-31.sh` — new sentinels.
6. `bash tests/integration/run.sh` — full platform baseline.
7. **Manual end-to-end** in a scratch project with `codex`/`gemini` on PATH:
   - `/vibeflow:onboard` → prints `▶ Next: /vibeflow:prd-quality-analyzer …`.
   - `/vibeflow:prd-quality-analyzer <PRD>` → report + `▶ Next: /vibeflow:phase-runner`.
   - `/vibeflow:phase-runner` → runs analyzer + `consensus-run.sh`, **produces a real verdict.json** (no deadlock), and either auto-advances (APPROVED) or prints the specialist/apply breadcrumb (NEEDS_REVISION). Confirm the old "BLOCKED — can't invoke disable-model-invocation chain" failure no longer occurs.

## Out of scope / deliberate non-goals

- Auto-running the **specialist → arbiter → apply** revision loop. Those rewrite the primary artifact (PRD/ADR) and stay operator-confirmed by design (Sprint 16 philosophy). phase-runner stops with a breadcrumb there.
- No `init` deprecation shim (would reintroduce the collision).
