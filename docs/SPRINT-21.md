# Sprint 21 — Signal-Quality Refinement: Semantic Excerption + Memory Compaction + Progress Ledger (v2.9.0)

> ✅ **COMPLETE** — shipped v2.9.0 on 2026-05-31. All seven tickets (S21-A..G) landed. Tests: sdlc-engine 168→173, hooks 133→139, new `sprint-21.sh` (65); total baseline 2379 → 2455 across 21 layers.

## Context

Sprints 14–20 built and closed VibeFlow's consensus loop end to end: CLI
reviewers (S14–15), the deterministic gate (S16), iteration (S17),
auto-satisfy (S18), primary-artifact refocus + `phase-runner` (S19), and
the L3 slow loop — consensus history mining + cross-session reviewer
memory (S20). The *mechanics* are complete. What's left in the deferred
backlog (named in both Sprint 19 and Sprint 20 "Out of Scope") is
**signal quality**: the loop works, but three of its inputs/outputs are
coarse.

1. **Excerption is positional, not relevance-based.** When a primary
   artifact exceeds ~30k tokens, `consensus-orchestrator` Step 2b
   (`skills/consensus-orchestrator/SKILL.md:57–68`) feeds reviewers the
   first 40% + last 15% + findings-anchored ±20-line windows. The
   most-contested section is often in the dropped middle, so reviewers
   review the wrong part of a large doc.
2. **Reviewer memory is pure recency.** The Sprint 20-D cap keeps the
   last N entries per `(reviewer, artifact)` and silently drops the
   rest (`hooks/scripts/consensus-aggregator.sh`). A critical raised 6
   rounds ago, then dropped from the cap, loses the "this keeps coming
   back" signal — exactly the signal worth escalating.
3. **`phase-runner` is invisible mid-run.** Progress is prose-only by
   design (`skills/phase-runner/SKILL.md:195` — "No runtime TUI"). On a
   long convergence walk (up to 3 × 5 reviewer rounds) the operator
   can't see which step is running or how many attempts are left.

**Goal:** sharpen all three — what reviewers *see* (semantic
excerption), what memory *keeps* (theme-aware compaction), and what the
operator *sees* (a structured progress ledger surfaced by
`/vibeflow:status`). No new loop mechanics; this is refinement of the
loop built in S14–20.

User direction (this session): **signal-quality refinement** bundle +
phase-runner visibility via a **structured progress ledger** (not a TUI).

## Design Overview — four groups, seven tickets

### Group 1 — Semantic primary-artifact excerption (S21-A)

Replace the positional head/tail excerpt with **section-scored
selection** for primaries over the token budget.

- Split the primary into sections by markdown headings (and form-feed /
  page breaks for `.docx`-derived text). Score each section by:
  - **evidence-finding density** — how many evidence findings
    (`target.file` / `target.line_range`) anchor into it;
  - **reviewer-memory hits** — sections whose text matches prior
    `criticals` from the Sprint 20-D store (reuse the memory the loop
    already has);
  - **evidence-summary keyword overlap** — Jaccard of section words vs
    the distilled evidence summaries.
- Always include the **first section** (title/overview) for context;
  fill the remaining budget with top-scored sections in document order.
- **Fallback:** a doc with no detectable section structure falls back
  to the existing head-40% / tail-15% behaviour — never worse than
  today.
- Formalize the prose `excerpt_if_large` into a concrete bash helper
  sketch in `consensus-orchestrator/SKILL.md` + a new scoring reference
  `skills/consensus-orchestrator/references/excerption.md`.
- **Harness `[S21-A]`:** section-scoring prose sentinels (evidence
  density, memory-hit, keyword overlap, first-section-always,
  head/tail fallback) + config-field presence.

### Group 2 — Reviewer-memory theme-aware compaction (S21-B)

When the Sprint 20-D cap would drop an entry, **fold it into a rolling
recurrence summary** instead of discarding it.

- Keep the most-recent N detailed entries **plus** one head
  `{type:"summary", primaryArtifact, recurringCriticals:[{title,
  seenCount, firstSeen, lastSeen}]}` per artifact. Dropped entries'
  criticals increment `seenCount` (matched by Jaccard title similarity,
  reusing the aggregator's existing `jaccard_title` idiom).
- `consensus-orchestrator` `build_memory_block` (Sprint 20-E) surfaces
  **recurring criticals first** (highest `seenCount`), then recent
  detail — so a long-standing unresolved objection leads the block.
- Implemented in `consensus-aggregator.sh` (the S20-D cap block) +
  `consensus-orchestrator/SKILL.md` (the render).
- **Harness `[S21-B]`:** hook-test runtime — drop past the cap, assert
  the summary entry appears, `seenCount` increments on recurrence, the
  newest detail survives; orchestrator render prose sentinel.

### Group 3 — Phase-runner progress ledger (S21-C, S21-D)

**S21-C — write the ledger.** `phase-runner` writes step-by-step state
to `.vibeflow/state/phase-runner-progress.json`:

```json
{
  "phase": "REQUIREMENTS", "startedAt": "…", "status": "running",
  "attempt": 1, "maxConvergenceAttempts": 3,
  "currentStep": "consensus-round-1",
  "steps": [
    { "name": "analyzer:prd-quality-analyzer", "status": "done", "startedAt": "…", "finishedAt": "…" },
    { "name": "consensus-round-1", "status": "running", "startedAt": "…", "detail": "agreement=0.78" }
  ]
}
```

Updated at each step boundary (analyzer, each consensus attempt,
specialist, apply, advance) and at terminal status
(`approved`/`stalled`/`rejected`/`advanced`). Reuses `vf_state_dir`.

**S21-D — surface it.** `/vibeflow:status` reads the ledger and renders
a "Phase-Runner Progress" section (current step, completed/total steps,
attempt N/max, terminal status). **Stale-guard:** ignore a ledger whose
`phase` ≠ the live phase or whose `startedAt` predates the last phase
advance — a stale ledger must not show a phantom run.

- **Harness `[S21-C]/[S21-D]`:** phase-runner prose writes ledger at
  each step boundary + terminal; status reads + renders + stale-guard;
  schema-key sentinels.

### Group 4 — Config, docs, tests, release

**S21-E — typed config.**
- Extend `ConsensusConfigSchema` (`config.ts`): `excerptTokenBudget`
  (default 30000), `excerptStrategy` (`"semantic" | "headtail"`,
  default `"semantic"`).
- Extend `ReviewerMemoryConfigSchema`: `compaction`
  (`"recency" | "theme-aware"`, default `"theme-aware"`).
- Unit tests mirror the S17-F / S19-G / S20-H schema-default +
  partial-merge pattern in `tests/config.test.ts`.

**S21-F — harness + hook tests + docs.**
- `tests/integration/sprint-21.sh` — **≈80 assertions** across
  `[S21-A]..[S21-Z]` + self-audit `[S21-Z]`.
- `hooks/tests/run.sh` — +≈6: memory compaction fold + seenCount;
  (excerption + ledger are skill-prose, covered by sprint-21.sh).
- Docs: new `docs/EXCERPTION.md` + `docs/PROGRESS-LEDGER.md`; refresh
  `docs/REVIEWER-MEMORY.md` (compaction) + `docs/CONSENSUS-FLOW.md`.

**S21-G — v2.9.0 release.**
- `.claude-plugin/plugin.json` + `marketplace.json`: 2.8.0 → 2.9.0.
- `@vibeflow/sdlc-engine`: 1.6.0 → 1.7.0 (config schema additions).
- `CHANGELOG.md` + `release-notes/2.9.0.md`; CLAUDE.md test counts +
  Sprint-21 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-21.md`
  COMPLETE; git tag `v2.9.0`.

## Files Touched (representative)

| Area | Files |
|---|---|
| Excerption (S21-A) | `skills/consensus-orchestrator/SKILL.md` (+`references/excerption.md`) |
| Memory compaction (S21-B) | `hooks/scripts/consensus-aggregator.sh`, `skills/consensus-orchestrator/SKILL.md` |
| Progress ledger (S21-C/D) | `skills/phase-runner/SKILL.md`, `skills/status/SKILL.md` |
| Config (S21-E) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests) |
| Tests/docs (S21-F) | `tests/integration/sprint-21.sh`, `hooks/tests/run.sh`, `docs/EXCERPTION.md`, `docs/PROGRESS-LEDGER.md`, `docs/REVIEWER-MEMORY.md`, `docs/CONSENSUS-FLOW.md` |
| Release (S21-G) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.9.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Verification (merge-green gate)

| Layer | Before (v2.8.0) | After (v2.9.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 168 | ~174 | +≈6 (excerpt + compaction schema fields) |
| `hooks/tests/run.sh` | 133 | ~139 | +≈6 (memory compaction fold) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1678 | ~1758 | +≈80 (sprint-21.sh) |
| **Total** | **2379** | **~2471** | **+≈92** |

Run before declaring any ticket done (per CLAUDE.md), with
`env -u VF_ALLOW_PHASE_WRITE` so the dogfood phase-guard tests still
exercise the block path: the 5 MCP `npm test` suites,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-21.sh`. Rebuild `sdlc-engine` dist after
the config change.

**E2E walk:** run `phase-runner` on a >30k-token PRD with prior reviewer
memory; confirm (1) reviewers receive section-scored excerpts that
include the memory-flagged sections, (2) a dropped past-cap critical
appears in the memory summary with `seenCount ≥ 2`, (3)
`.vibeflow/state/phase-runner-progress.json` updates per step and
`/vibeflow:status` renders the current step + attempt, (4) all defaults
hold with an empty `vibeflow.config.json`.

## Out of Scope (→ Sprint 22+)

- **Interactive TUI / live progress bar.** Skills are prose+bash; the
  ledger + `/vibeflow:status` is the realistic surface. A real TUI would
  need a host-side renderer — Sprint 22+.
- **Acting on the learning loop** (auto-tuning config / templates from
  `consensus-learning-report.md`). The "close the action gap" theme —
  Sprint 22 candidate.
- **Embedding-based excerption / memory** (true semantic vectors).
  Sprint 21 uses lexical scoring (Jaccard + finding-density); vector
  scoring needs an embeddings dependency — deferred.
- **Auto-satisfy for `design.approved` / `accessibility.verified` /
  `sprint.planned`** — stays manual per the Sprint 18 decision.
