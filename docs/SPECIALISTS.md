# Phase Specialists (Sprint 17-D/E)

VibeFlow v2.5.0 adds six phase-specialist subagents and a
dispatcher skill that forks the right one based on the project's
current SDLC phase. Specialists are the **deep-rewrite** arm of the
consensus loop — the arbiter produces mechanical patches from
reviewer `suggestions[]`, specialists produce one large patch that
restructures the artifact.

## When to use

The orchestrator's follow-up prose on NEEDS_REVISION or
HUMAN_APPROVAL_REQUIRED shows both options:

```
Next options:
  /vibeflow:consensus-arbiter <sid>       — mechanical diff-first patches
  /vibeflow:consensus-specialist <sid>    — deep rewrite by <phase-specialist>
```

Pick the arbiter when reviewer suggestions are concrete ("fix line
42 to use `Decimal` instead of `float`"). Pick the specialist when
suggestions read like "this whole section is underspecified and
needs a rewrite."

You can run arbiter first, apply, then trigger a fresh consensus
session and run specialist on that — or vice-versa. They produce
non-overlapping patches in the same session dir, and
`apply-arbiter-patch` processes them in `manifest.json` order.

## The 6 agents

| Phase | Agent | Reads | Produces |
|---|---|---|---|
| **REQUIREMENTS** | `prd-rewriter` | PRD + quality-report + reviewer suggestions | PRD rewrite patch |
| **DESIGN** | `design-spec-refiner` | design spec + reviewer + accessibility findings | design spec rewrite patch |
| **ARCHITECTURE** | `adr-author` | architecture-report + reviewer + policy violations | new ADR + architecture.md updates |
| **PLANNING** | `test-strategy-refiner` | test-strategy + scenario-set + reviewer + RTM | scenario-set expansion patch |
| **TESTING** | `coverage-gap-filler` | coverage + mutation + reviewer | new test files / assertions |
| **DEPLOYMENT** | `runbook-editor` | release-decision + runbooks + incident notes + reviewer | runbook + rollback updates |

Every agent shares the same frontmatter:

```yaml
---
name: <agent-name>
description: <one-line>
model: opus
effort: high
context: fork
---
```

## Dispatcher

`/vibeflow:consensus-specialist [<session-id>]` reads
`vibeflow.config.json.currentPhase` and forks the matching agent.
Default session id: the most recent `.verdict.json` under
`.vibeflow/state/consensus/`.

The dispatcher skill lives at
`skills/consensus-specialist/SKILL.md` and emits:

- One unified diff at
  `.vibeflow/state/patches/<sid>/specialist-NN-<phase>.patch`
- A decision report at
  `.vibeflow/reports/specialist-decisions-<phase>.md`
- A `manifest.json` entry with `type: "specialist"` so
  apply-arbiter-patch processes it in order alongside arbiter
  patches

After the specialist returns, the dispatcher prints a follow-up
hint:

```
Specialist prd-rewriter produced 1 patch:

  .vibeflow/state/patches/9f3a…/specialist-01-requirements.patch
     affects: docs/FlowBridge_TR_SRS_v1_1.docx (+58, -12)
     addresses: 7 findings, deferred 3
     rationale: see .vibeflow/reports/specialist-decisions-requirements.md

Next:
  /vibeflow:apply-arbiter-patch 9f3a…
      (shows diff preview → y/n → git apply; add --run-tests
       to verify tests pass post-apply)

Rollback (if applied patch breaks something):
  git checkout HEAD -- docs/FlowBridge_TR_SRS_v1_1.docx
```

## Invariants (all agents)

- **Diff-first.** Agents never write to source files directly —
  their outputs are patch files + decision reports under
  `.vibeflow/state/patches/` and `.vibeflow/reports/`.
- **Phase-scoped.** Each agent refuses to run if
  `currentPhase` doesn't match its declared phase; it emits
  "specialist X only runs in Y. Current phase: Z. Stopping."
- **Single patch per invocation.** No multi-patch output — if a
  session needs both arbiter + specialist, run them separately.
- **Scope = findings envelope.** Agents only rewrite what
  reviewers actually flagged. No tangential cleanup, no
  opportunistic refactor.
- **No slash-command invocation.** `context: fork` subagents
  can't dispatch slash commands; the operator makes the apply
  call explicitly.

## Decision heuristics (per agent)

Each agent has its own prioritised rule set. The full list lives
in `agents/<name>.md` under "Decision Heuristics". A few concrete
highlights:

### prd-rewriter (REQUIREMENTS)

Priority: structural gaps flagged by ≥2 reviewers → domain hard
blocks → missing flows (MF-codes) → ambiguities (AMB-codes) →
conflicts (CONF-codes). Vague verbs become testable predicates
with numeric thresholds.

### adr-author (ARCHITECTURE)

Drafts new ADR files with sequential numbers
(`docs/adr/NNNN-<slug>.md`) when reviewers disagree on a
contested decision. Captures trade-offs + chosen path + dissent.
Never rewrites historical ADRs — new decisions get new files
with a Superseded reference.

### coverage-gap-filler (TESTING)

Matches `tech.testRunner` (vitest / jest / pytest / dotnet) to
pick assertion style. Targets P0-uncovered paths first; picks
the lowest-friction test level (unit > contract > e2e) that
still covers the path.

### runbook-editor (DEPLOYMENT)

Never touches CI / pipeline config — that's out of scope for
this specialist and needs ops-team review. Focuses on
rollback recipes + release-notes gaps + health-check drift +
incident-lesson capture.

## Rollback

Every specialist patch is a single `git apply`. If the applied
patch breaks a build or a test:

```bash
git checkout HEAD -- <affected files>
```

The decision report names the affected files in a rollback
section. The raw reviewer input (session jsonls) stays on disk,
so re-running the specialist produces a fresh patch without
starting a new consensus session.

`apply-arbiter-patch --run-tests` surfaces test failures
immediately post-apply and prints the rollback line — the skill
never auto-reverts (we'd rather leave recovery to you than
compound the damage with a guess).

## Guardrails

- **Only one specialist per session.** If `manifest.json`
  already has a `type: "specialist"` entry, the dispatcher
  refuses to run again unless `--force` is passed. Two
  specialists on the same verdict = conflicting patches.
- **Marker drain on success.** Dispatcher removes
  `consensus-needed.json` + `review-pending.json` so the
  subsequent apply-arbiter-patch call isn't blocked by the
  Sprint 16 PreToolUse hook.
- **No phase inference.** If `currentPhase` is wrong, run
  `/vibeflow:status` and `/vibeflow:advance` to correct it
  first — don't rely on the dispatcher to guess.

## Adding a new specialist

The agents are plain markdown files under `agents/`. To add a
seventh specialist (e.g. a PRODUCT-LAUNCH agent):

1. Copy one of the existing agents as a template.
2. Update `name`, `description`, `Phase Contract`, and
   `Decision Heuristics` for the new role.
3. Add an entry to the phase-to-agent map in
   `skills/consensus-specialist/SKILL.md`.
4. Register the new skill in `skills/phase-policy.json` under
   the right phase list.
5. Add a `[S17-D] <agent>` block to
   `tests/integration/sprint-17.sh`.

The dispatcher only fires when `currentPhase` maps to a known
agent — missing entries fall through to a "no specialist for
this phase" message without running anything.
