---
name: flow-status
description: Shows current VibeFlow project status including SDLC phase, pending tasks, quality metrics, and recent review results. Use when asking about project progress. Renamed from `status` in v2.20.0 to avoid colliding with Claude Code's built-in `/status` (usage/quota).
allowed-tools: Read Grep Glob AskUserQuestion Bash(bash *loop-audit.sh*) Bash(bash *ui-verification-debt.sh*) Bash(bash *streams-audit.sh*) Bash(jq *)
---

# VibeFlow Flow-Status

Read vibeflow.config.json and .vibeflow/ directory to compile project status.

## Report Sections

### 1. Current Phase
- Active SDLC phase (REQUIREMENTS through DEPLOYMENT)
- Phase progress (iteration X of max Y)

### 2. Quality Metrics
- Latest testability score (from prd-quality-analyzer)
- Test coverage percentage (from coverage-analyzer)
- Traceability score (from traceability-engine)
- Last consensus result and score

### 3. Pending Tasks
- Incomplete tasks in current phase
- Blocked items requiring attention
- Upcoming quality gates

### 4. Recent Activity
- Last 5 reviews with verdicts
- Last phase transition timestamp
- Recent skill invocations

### 5. Phase-Runner Progress (Sprint 21-D)
If `.vibeflow/state/phase-runner-progress.json` exists, render a
"Phase-Runner Progress" block from it:

- `currentStep` and `status` (running / approved / stalled / rejected /
  advanced / blocked)
- `attempt` of `maxConvergenceAttempts`
- completed vs total `steps[]` (e.g. "4 of 6 steps") with each step's
  `name` + `status` + `detail`

**Stale-guard — do not show a phantom run.** Skip the block entirely
when the ledger is stale:
- its `phase` ≠ the live `currentPhase` (a leftover ledger from an
  earlier phase), **or**
- its `startedAt` predates the last phase-transition timestamp (the
  run finished and the phase already advanced past it).

A ledger whose `status` is terminal (`advanced` / `approved` /
`rejected`) for the *current* phase may still be shown as the last
completed run, clearly labelled "last run" rather than "in progress".

### 6. Autonomous Loop (Sprint 25-B)
Run the read-only audit reader and render the autonomous-loop state from
its JSON:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-audit.sh"
```

It consolidates the scattered telemetry (`history.jsonl` auto-apply
outcomes, `auto-apply/cooldown-*` markers, `auto-apply/watch.json`,
`consensus-learning-report.md`, `learning-apply-decisions.md`). Render:

- **Auto-apply tally** — `applied` / `held` / `reverted` over the
  `loopAudit.window` recent rows, with a **per-key revert rate**. Flag
  any key whose `revertRate ≥ 0.5` as *"candidate for removal from
  `autoApply.keys`"* (the same signal the S24-B `auto-tune-ineffective`
  detector raises).
- **Cooled-down keys** (`autoApply.cooldowns`) — won't re-tune this sprint.
- **Armed watch** (`autoApply.armedWatch`) — a tune awaiting next-round
  judgement (its `keys` + phase + primaryArtifact), if any.
- **Learning report** — `learning.findingCount` findings; remind the
  operator to read it via
  `/vibeflow:learning-loop-engine --mode consensus-history`.
- **Recent decisions** — the last few `recentDecisions` from
  `learning-apply`.

**Idle collapse.** When the reader returns all zeros / empties (no
`applied`, no `cooldowns`, no `armedWatch`, `reportExists:false`), render
a single line — `Autonomous loop: idle (autoApply off / no activity)` —
so projects that don't use auto-apply see no noise.

### 7. UI render-verification (Sprint 54)
Run the read-only reader and render a one-liner **only when there's debt**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/ui-verification-debt.sh" .
```

- `"never"` → `⚠ Web UI never render-verified — run /vibeflow:frontend-render-check`
- `"stale"` → `⚠ UI changed since last render-verification — re-run /vibeflow:frontend-render-check`
- `"verified"` / `"no-ui"` → render nothing (no web UI, or it's verified).

This catches a UI built in an earlier cycle that shipped coverage-tested but was
never rendered or compared to its design — so it can't stay buried.

### 8. Work-streams (Sprint 60)
**Only when `streams.enabled` is on**, run the read-only reader and render a
one-liner naming how many parallel work-streams have local state:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/streams-audit.sh"
```

- `streamsEnabled: false` → render nothing (single-stream project).
- otherwise → `Work-streams: <N> active (current: <currentStreamId>) — /vibeflow:streams`
  and, if `conflicts[]` is non-empty, append `⚠ <K> shared-branch conflict(s)`.

This is the quick glance; `/vibeflow:streams` is the full per-stream dashboard.

### 9. UI Quality — design-guard bridge

If the optional **design-guard** plugin is in use, its `design-auditor`
verdicts are recorded into the same `history.jsonl` as a `design-guard-audit`
row. Read the latest one and render surface-only (nothing when absent — a
project without design-guard is unaffected):

```bash
jq -c 'select(.type=="design-guard-audit")' .vibeflow/state/consensus/history.jsonl 2>/dev/null | tail -1
```

- no row → render nothing (design-guard not in use, or no audit yet).
- `verdict == "FIXES_REQUIRED"` → `⚠ design-guard: FIXES REQUIRED (<blockers> blocker(s)) — run the design-auditor agent on the changed UI`.
- `verdict == "SHIPPABLE"` → one quiet line `UI quality: SHIPPABLE (design-guard, <age>)`.

design-guard is a **separate plugin**; this section only reads a file it may
have written, so VibeFlow never depends on it being installed.

## Output
Display a concise status summary directly in the conversation. Do not create a file.

### Next step — as a tappable choice, not a prose breadcrumb (Sprint 63)

**Operator choice (mobile-friendly — see `docs/OPERATOR-CHOICES.md`).** When the
status surfaces a **clear next action**, present it with the **`AskUserQuestion`**
tool as 2–4 tappable options instead of (or right after) a bare "Next step:" line,
so the operator can act with one tap from a phone. Lead with the recommended
option; always include a **"Stay / do nothing"** option; the built-in "Other"
lets them type. Derive the options from what the report found, e.g.:

- a **phase advance is available** (all exit criteria for the current phase met) →
  **Advance to `<next phase>`** (`/vibeflow:advance`) · Stay.
- a **branch/increment or cycle mismatch** was flagged → **Advance anyway** ·
  **Fix the mismatch first** (name it) · Stay.
- **UI render-verification debt** (`never`/`stale`) → **Run
  `/vibeflow:frontend-render-check`** · Stay.
- **work-streams** with a recommended action → **Open `/vibeflow:streams`** · Stay.

Put the condensed "why" (the relevant finding) in each option's description so the
operator decides without scrolling the full report. When there is **no** actionable
next step, omit the card (don't invent one). This is a read-only surfacing — it
never changes state; picking an option just launches the named command.
