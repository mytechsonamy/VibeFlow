# Sprint 27 — Template-Route Autonomy: Propose-Only Specialist Auto-Fork (v2.15.0)

> ✅ **COMPLETE** — shipped v2.15.0 on 2026-06-05 (backlog B1). Five tickets (S27-A..E) landed. Tests: sdlc-engine 194→196, new `sprint-27.sh` (44); total baseline 2740 → 2786 across 27 layers.

## Context

The L3 "act" arc is complete for **config** changes (learning-apply →
diff-first config patch → optional bounded auto-apply + auto-revert,
Sprints 22–24). But the **template lane** is still fully manual: when the
learning loop finds a `recurring-suggestion-theme` (the same theme across
≥3 artifacts — a systemic PRD/ADR/test-strategy gap, not a config knob),
`learning-apply`'s Step 4 only **writes a recommendation** to run
`/vibeflow:consensus-specialist` by hand
(`skills/learning-apply/SKILL.md` — "does NOT fork the specialist
itself"). The operator has to notice it and invoke the specialist
manually.

Sprint 27 closes that gap — **propose-only**. When opted in, the
template-route lane **auto-forks the matching phase specialist** on the
affected artifact, producing a diff-first patch. The patch is **never
applied automatically**: it lands under `.vibeflow/state/patches/` and the
operator confirms it via `/vibeflow:apply-arbiter-patch` (the same safety
posture as Sprint 22 config-tune). No source/template is written without
confirmation. Default off, so today's recommend-only behaviour is
unchanged for anyone who doesn't opt in.

User direction (this session): **B1 template-route autonomy**, **propose-
only / diff-first** (auto-fork the specialist; the operator still confirms
the apply — no auto-apply for templates).

## What exists vs. what's missing

- `consensus-specialist` (S17-E) + the six phase-specialist agents
  (prd-rewriter, adr-author, …, S17-D) already produce **diff-first
  patches** under `.vibeflow/state/patches/` and feed
  `/vibeflow:apply-arbiter-patch` for preview+confirm+apply. **Reuse all
  of it.**
- The phase-specialist agents are **consensus-session-driven** — they
  read `verdict.json` + reviewer `suggestions[]`. They don't yet accept a
  *learning-loop finding* as the rewrite brief. That bridge is the new
  work.

## Design Overview — five groups, five tickets

### Group 1 — Config: `autoForkSpecialist` opt-in (S27-A)

`LearningApplyConfigSchema` (`config.ts`) += `autoForkSpecialist:
z.boolean().default(false)`. Default **off** ⇒ template-route stays
recommend-only (Sprint 22-C). Unit tests (default + partial-merge),
mirroring the `autoApply` opt-in shape.

### Group 2 — learning-apply auto-fork lane (S27-B)

Rework `learning-apply` Step 4 (template-route):

- **`autoForkSpecialist` false (default):** unchanged — write the
  `/vibeflow:consensus-specialist` dispatch recommendation into
  `learning-apply-decisions.md`.
- **`autoForkSpecialist` true:** write a **learning-fork brief** to
  `.vibeflow/state/patches/learning-fork-<ts>/brief.md` (the recurring
  theme title, the affected `primaryArtifact`, the rationale, the
  `seenCount`, and a pointer to `consensus-learning-report.md`), then
  **fork the matching phase specialist** (per the existing phase→agent
  map in `references/lanes.md`) pointing it at the brief + artifact. The
  specialist emits its diff-first patch as usual. Record in the decisions
  report as `Specialist forked: <agent> on <artifact> → patch at <dir>;
  apply with /vibeflow:apply-arbiter-patch` — and **stop there**.
  learning-apply NEVER applies the patch.

Guardrails: only `recurring-suggestion-theme` findings that clear
`minObservations` fork; one fork per theme per run; respects the
`learningApply.enabled` kill switch.

- **Harness `[S27-B]`:** auto-fork prose + brief path + "patch not
  applied / operator confirms via apply-arbiter-patch" guardrail +
  recommend-only-when-off back-compat sentinel.

### Group 3 — Phase specialists accept a learning-fork brief (S27-C)

The six phase-specialist agents (`agents/prd-rewriter.md`, etc.) gain a
short **additive** "Alternative trigger (Sprint 27)" note in their Input
Contract: they may be forked by `learning-apply` with a *learning-fork
brief* (a `recurring-suggestion-theme` finding) **instead of** a consensus
session. In that mode: treat the theme as the structural gap to resolve,
read the named artifact, and emit the same **one diff-first patch** under
`.vibeflow/state/patches/<fork-dir>/` — never writing source directly.
A new `agents/_shared/learning-fork-brief.md` documents the brief format
once (the agents reference it, so the per-agent note stays 2–3 lines).

- **Harness `[S27-C]`:** shared brief-format doc exists; each specialist
  references the learning-fork trigger; diff-first/never-write-source
  contract still present.

### Group 4 — Docs + harness (S27-D)

- New `docs/TEMPLATE-AUTONOMY.md` — the template-route lane end to end
  (finding → auto-fork → specialist diff-first patch → operator apply),
  the propose-only guarantee, the `autoForkSpecialist` opt-in, and why
  templates stay confirm-only (unlike config's bounded auto-apply).
  Refresh `docs/ACTION-GAP.md` + `docs/LEARNING-APPLY.md`.
- `tests/integration/sprint-27.sh` — **≈50 assertions** across
  `[S27-A]..[S27-Z]` + self-audit `[S27-Z]` (config sentinels + runtime
  default probe + skill/agent prose sentinels).

### Group 5 — Release (S27-E)

- `.claude-plugin/plugin.json` + `marketplace.json`: 2.14.0 → 2.15.0.
- `@vibeflow/sdlc-engine`: 1.12.0 → 1.13.0 (`autoForkSpecialist`).
- `CHANGELOG.md` + `release-notes/2.15.0.md`; CLAUDE.md test counts +
  Sprint-27 ✅ COMPLETE; ROADMAP appendix row + tick B1 in the backlog;
  mark `docs/SPRINT-27.md` COMPLETE; commit + tag `v2.15.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Config (S27-A) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests) |
| Auto-fork lane (S27-B) | `skills/learning-apply/SKILL.md` (+ `references/lanes.md`) |
| Specialist brief (S27-C) | `agents/prd-rewriter.md` + 5 sibling agents, `agents/_shared/learning-fork-brief.md` (new) |
| Docs/harness (S27-D) | `tests/integration/sprint-27.sh`, `docs/TEMPLATE-AUTONOMY.md`, `docs/ACTION-GAP.md`, `docs/LEARNING-APPLY.md` |
| Release (S27-E) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.15.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Diff-first specialist patches + apply-arbiter-patch confirm** —
  S17-D/E + S15-G. The auto-fork only *triggers* the specialist; the
  patch path + operator confirmation are unchanged.
- **phase→specialist map** — `references/lanes.md` (S22-C) /
  `consensus-specialist/SKILL.md` (S17-E).
- **Opt-in default-off config** — `autoApply` (S23-A); `autoForkSpecialist`
  is the same shape.

## Verification (merge-green gate)

| Layer | Before (v2.14.0) | After (v2.15.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 194 | ~197 | +≈3 (autoForkSpecialist) |
| `hooks/tests/run.sh` | 167 | 167 | 0 |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1994 | ~2044 | +≈50 (sprint-27.sh) |
| **Total** | **2740** | **~2793** | **+≈53** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-27.sh`. Rebuild `sdlc-engine` dist.

**E2E walk:** seed a `consensus-learning-report.md` with a
`recurring-suggestion-theme` finding (≥3 artifacts) in REQUIREMENTS; run
`learning-apply` with `autoForkSpecialist:false` → confirm it only
*recommends* `/vibeflow:consensus-specialist` (unchanged); set
`autoForkSpecialist:true` → confirm it writes a learning-fork brief, forks
`prd-rewriter`, the specialist emits a diff-first PRD patch under
`.vibeflow/state/patches/learning-fork-*/`, the decisions report says
"apply with /vibeflow:apply-arbiter-patch", and **nothing is written to
the PRD** until the operator runs apply-arbiter-patch.

## Out of Scope (→ Sprint 28+)

- **Bounded auto-apply for template patches** (no operator confirm) —
  deliberately rejected this session; templates stay confirm-only.
- **Cross-project meta-learning** (B2), **embedding-based excerption**
  (B3), **live TUI** (B4), **phase-runner TESTING auto-run** (B5) —
  unchanged backlog.
