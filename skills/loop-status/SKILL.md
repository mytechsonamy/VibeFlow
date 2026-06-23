---
name: loop-status
description: The autonomous-loop dashboard. Consolidates every loop surface — phase-runner progress, auto-apply outcomes + per-key revert rates, cooled-down keys, the armed revert watch, learning-report findings, and the opt-in cross-project signal — into one read-only view, and writes a durable .vibeflow/reports/loop-status.md audit. Where /vibeflow:flow-status gives a quick inline glance, /vibeflow:loop-status is the full pane of glass. Read-only — never changes config or source.
allowed-tools: Read Write Grep Glob AskUserQuestion Bash(bash *loop-audit.sh*) Bash(jq *)
---

# Loop Status — the autonomous-loop dashboard (Sprint 30)

After Sprints 20–29, the autonomous loop's state lives across several
files. `/vibeflow:flow-status` shows a quick *inline* glance; this skill is the
**full pane of glass** — one consolidated, read-only dashboard, plus a
durable written audit.

## Step 1 — Read the consolidated audit

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-audit.sh"
```

`loop-audit.sh` (read-only, fully guarded) returns one JSON document with
every loop surface: `autoApply` (applied/held/reverted + armedWatch +
cooldowns), `perKey` (per-key counts + `revertRate` + `cooledDown`),
`learning` (finding count), `recentDecisions`, `phaseRunner` (the
Sprint-21 progress ledger), and `crossProject` (the Sprint-28 signal, when
`globalLearning.enabled`).

## Step 2 — Render the dashboard

Render the JSON as a single human dashboard, in this order:

```
VibeFlow Autonomous Loop — <project> @ <currentPhase>

  Phase-runner:   <phaseRunner.status> · step <currentStep> · attempt <attempt>/<maxConvergenceAttempts>
                  <stepsDone>/<stepsTotal> steps        (or "idle — no run" when phaseRunner is null)
  Auto-apply:     applied <A> · held <H> · reverted <R>
    per key:      <key>   a/h/r   revertRate=<r>   [cooled-down]   [⚠ candidate for removal]
  Cooled-down:    <autoApply.cooldowns…>
  Armed watch:    <autoApply.armedWatch.keys> @ <phase>   (or "none")
  Learning:       <learning.findingCount> findings  → /vibeflow:learning-loop-engine --mode consensus-history
  Cross-project:  <key>  held in <projects> projects  holdRate=<r>  (recommendation only)
                  (shown only when crossProject is non-null / globalLearning on)
  Recent:         <recentDecisions… last few>
```

- Flag any `perKey` entry with `revertRate ≥ 0.5` as **⚠ candidate for
  removal from `autoApply.keys`** (the S24-B / S25-B signal).
- Surface each `crossProject.perKey` entry as a **recommendation only** —
  state explicitly it does NOT auto-allowlist.
- **Idle collapse.** When `autoApply.applied == 0`, no cooldowns, no
  armed watch, `learning.reportExists == false`, AND `phaseRunner` is
  null, render a single line: `Autonomous loop: idle (no activity).`

## Step 3 — Write the durable audit

Write the same content as Markdown to
`.vibeflow/reports/loop-status.md` — a shareable "loop pane of glass" the
operator (or CI) can read without re-running the skill. Header with the
project + phase + a UTC timestamp, then the same sections.

## Next step — as a tappable choice (Sprint 63)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When the
dashboard surfaces a **clear recommended action**, present it with the
**`AskUserQuestion`** tool as 2–4 tappable options (recommended first, condensed
rationale per option, always a **"Stay / do nothing"** option; "Other" lets the
operator type) instead of a bare prose next-step. Typical cases:

- a `perKey` entry at `revertRate ≥ 0.5` → **Remove `<key>` from `autoApply.keys`**
  (via `/vibeflow:learning-apply`) · Stay.
- a cross-project signal recommendation → surface it as a **recommendation-only**
  option (state it does NOT auto-allowlist) · Stay.
- pending learning findings → **Run `/vibeflow:learning-apply`** · Stay.

Omit the card when the loop is idle / there's nothing actionable. Read-only —
picking an option just launches the named command; it changes nothing itself.

## Read-only

`loop-status` **never** changes `vibeflow.config.json`, `autoApply.keys`,
or any source/artifact. Its only write is the
`.vibeflow/reports/loop-status.md` audit. The cross-project signal and the
revert-rate flags are *recommendations*; acting on them is the operator's
call (via `learning-apply` / editing `autoApply.keys`).

## When to use

- `/vibeflow:flow-status` → a quick "where am I + is the loop doing anything"
  inline glance (its Autonomous Loop section).
- `/vibeflow:loop-status` → the full dashboard + a durable report, when
  you want to audit *everything the loop has done* in one place.

## See also

- `docs/LOOP-STATUS.md` — the dashboard reference.
- `docs/LOOP-AUDIT.md` — the reader this skill renders.
- `docs/CROSS-PROJECT-LEARNING.md` — the cross-project signal.
