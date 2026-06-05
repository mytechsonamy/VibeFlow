# Sprint 30 — Loop-Status Dashboard (Capstone, v2.18.0)

> ✅ **COMPLETE** — shipped v2.18.0 on 2026-06-05 (backlog B4, capstone). Four tickets (S30-A..D). Skill + hook only (no engine change). Tests: new `sprint-30.sh` (58), `hooks/tests/run.sh` 174 → 185 (+11); total baseline 2874 → 2943 across **30** test layers. **Backlog cleared — B1/B2/B4/B5 all shipped; the autonomous-loop arc is feature-complete. B3 (embedding excerption) remains a deliberate non-goal.**

## Context

This is the final backlog item (**B4**) — and a natural capstone. Sprints
20–29 built a deep autonomous loop whose state is now spread across
several surfaces:

- `loop-audit.sh` (S25-A) → auto-apply tally, per-key revert rates,
  cooldowns, armed watch, learning finding count, recent decisions —
  rendered as one *section* of `/vibeflow:status`.
- `phase-runner-progress.json` (S21-C) → the live/last phase-runner walk,
  rendered as a *separate section* of `/vibeflow:status`.
- `consensus-learning-report.md` (S20) → the slow-loop findings.
- `global-learning.jsonl` (S28) → cross-project signal (opt-in).

No single command answers "**what is the autonomous loop doing, across
all of it?**" — `/vibeflow:status` mixes loop state with phase/quality
status, and the cross-project signal isn't surfaced at all. B4 gives the
loop its own dashboard: a dedicated **`/vibeflow:loop-status`** that
consolidates every loop surface into one human view **and** writes a
durable `.vibeflow/reports/loop-status.md` audit. Read-only — it never
changes anything.

User direction (this session): **B4 loop-status dashboard** — finish here.

## Design Overview — four groups, four tickets

### Group 1 — Extend `loop-audit.sh` with the missing surfaces (S30-A)

`loop-audit.sh` already emits `{autoApply, perKey, learning,
recentDecisions}`. Add two sections (keep all existing fields so
`/vibeflow:status` is unaffected):

- **`phaseRunner`** — from `.vibeflow/state/phase-runner-progress.json`
  (if present): `{phase, status, currentStep, attempt,
  maxConvergenceAttempts, stepsDone, stepsTotal}`; `null` when absent.
- **`crossProject`** — only when `globalLearning.enabled`, from
  `$(vf_global_dir)/global-learning.jsonl`: `{distinctProjects,
  perKey:[{key, projects, holdRate}]}` (reuse the Sprint-28 aggregation).
  `null`/empty when off or absent.

Guarded, read-only, degrades to nulls on a fresh project.

- **Harness `[S30-A]`:** hook-test runtime — seed a progress ledger + a
  global store; assert the reader's `phaseRunner` + `crossProject`
  sections populate; absent ⇒ `null`; the existing fields still present.

### Group 2 — `/vibeflow:loop-status` skill (S30-B)

New `skills/loop-status/SKILL.md` (phases: ALL, read-only). Runs
`loop-audit.sh` and renders **one consolidated dashboard**:

```
VibeFlow Autonomous Loop — <project> @ <phase>

  Phase-runner:   <status> · step <currentStep> · attempt N/max  (or "idle")
  Auto-apply:     applied A · held H · reverted R
    per key:      <key>  applied/held/reverted  revertRate  [cooled-down] [⚠ candidate-removal]
  Cooled-down:    <keys>            Armed watch: <keys> @ <phase>
  Learning:       N findings  (run /vibeflow:learning-loop-engine --mode consensus-history)
  Cross-project:  <key> held M/P projects  (recommendation only)   [if globalLearning on]
  Recent:         <last decisions>
```

It also **writes `.vibeflow/reports/loop-status.md`** — the same content
as a durable, shareable audit (a "loop pane of glass"). Invoked as
`/vibeflow:loop-status`. Flags `revertRate ≥ 0.5` keys + surfaces the
cross-project recommendation. Idle collapse when nothing has happened.
Register in `skills/phase-policy.json` (ALL, read-only).

- **Harness `[S30-B]`:** skill exists + frontmatter; runs `loop-audit.sh`;
  renders phase-runner + auto-apply + cooldowns + learning + cross-project
  + recent; writes `.vibeflow/reports/loop-status.md`; idle-collapse;
  phase-policy registration; read-only (no Write to config/source).

### Group 3 — Docs + harness (S30-C)

- New `docs/LOOP-STATUS.md` — the dashboard, what each line means, the
  written report, how it relates to `/vibeflow:status`' Autonomous Loop
  section (status = quick inline glance; loop-status = the full pane +
  durable report). Refresh `docs/LOOP-AUDIT.md` (the reader now feeds two
  surfaces).
- `tests/integration/sprint-30.sh` — **≈45 assertions** across
  `[S30-A]..[S30-Z]` + self-audit `[S30-Z]` (reader-section sentinels +
  skill prose + docs + a consolidated-JSON runtime probe).
- `hooks/tests/run.sh` — +≈5 (loop-audit `phaseRunner` + `crossProject`
  sections, present + absent).

### Group 4 — Release (S30-D — v2.18.0, capstone)

- `.claude-plugin/plugin.json` + `marketplace.json`: 2.17.0 → 2.18.0.
- `@vibeflow/sdlc-engine`: unchanged (skill + hook only).
- `CHANGELOG.md` + `release-notes/2.18.0.md`; CLAUDE.md test counts +
  Sprint-30 ✅ COMPLETE; ROADMAP appendix row + tick **B4** (backlog now
  fully cleared — note the project is feature-complete); mark
  `docs/SPRINT-30.md` COMPLETE; commit + tag `v2.18.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Reader (S30-A) | `hooks/scripts/loop-audit.sh` (+ `hooks/tests/run.sh`) |
| Skill (S30-B) | `skills/loop-status/SKILL.md` (new), `skills/phase-policy.json` |
| Docs/harness (S30-C) | `tests/integration/sprint-30.sh`, `docs/LOOP-STATUS.md`, `docs/LOOP-AUDIT.md` |
| Release (S30-D) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `release-notes/2.18.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Guarded jq reader → JSON** — `loop-audit.sh` (S25-A); S30-A adds two
  sections in the same style, reusing the Sprint-28 cross-project
  aggregation jq and the Sprint-21 ledger shape.
- **`/vibeflow:status` renders a reader's JSON** — S25-B / S21-D; the new
  skill is the same render pattern, just dedicated + with a written report.
- **Read-only skill + phase-policy ALL** — `status` / `repo-fingerprint`.

## Verification (merge-green gate)

| Layer | Before (v2.17.0) | After (v2.18.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 199 | 199 | 0 (no engine change) |
| `hooks/tests/run.sh` | 174 | ~179 | +≈5 (phaseRunner + crossProject sections) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~2116 | ~2161 | +≈45 (sprint-30.sh) |
| **Total** | **2874** | **~2924** | **+≈50** |

Run with `env -u VF_ALLOW_PHASE_WRITE` (and `VIBEFLOW_GLOBAL_DIR` at a
temp dir for the cross-project probe): 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-30.sh`.

**E2E walk:** seed a project with auto-apply history + a
`phase-runner-progress.json` + (globalLearning on) a `global-learning.jsonl`;
run `loop-audit.sh` → confirm `phaseRunner` + `crossProject` sections
populate; run `/vibeflow:loop-status` → confirm the consolidated dashboard
shows phase-runner progress + auto-apply tally + revert-rate flags +
cooldowns + learning findings + cross-project recommendation, and writes
`.vibeflow/reports/loop-status.md`; on a fresh project → idle collapse +
all-null sections.

## Out of Scope (capstone — backlog closed)

- **B3 embedding-based excerption** — intentionally NOT built: it trades
  away VibeFlow's deterministic / no-external-dependency core posture.
  Documented as a deliberate non-goal, not a TODO.
- **A real redrawing terminal TUI** — skills are prose+bash; the
  consolidated dashboard + written report is the realistic surface. A
  host-side renderer is outside the plugin model.
