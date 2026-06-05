# Loop Status — the autonomous-loop dashboard (Sprint 30)

By Sprint 29 the autonomous loop reached deep across the SDLC — mining
consensus history, tuning config, auto-applying and auto-reverting,
self-demoting, sharing a privacy-safe signal across projects, and walking
whole phases unattended. Its *state*, though, lived in half a dozen
files. `/vibeflow:flow-status` showed a slice; nothing showed all of it.

**`/vibeflow:loop-status`** is the capstone: one read-only **dashboard**
that consolidates every loop surface, plus a durable
`.vibeflow/reports/loop-status.md` audit you can share or feed to CI.

## The two surfaces

| Command | Scope | Output |
|---|---|---|
| `/vibeflow:flow-status` → Autonomous Loop | a *quick inline glance* (am I looping, anything pending?) | inline, no file |
| `/vibeflow:loop-status` | the *full pane of glass* — every surface | inline **+** `.vibeflow/reports/loop-status.md` |

Both render the same reader — [`loop-audit.sh`](LOOP-AUDIT.md). The
dashboard simply uses every field (including `phaseRunner` +
`crossProject`, added in Sprint 30-A) and writes a report.

## The dashboard

```
VibeFlow Autonomous Loop — <project> @ <currentPhase>

  Phase-runner:   running · step consensus-round-1 · attempt 2/3 · 1/2 steps
  Auto-apply:     applied 3 · held 1 · reverted 2
    per key:      consensus.maxIterations  3/1/2  revertRate=0.67  cooled-down  ⚠ candidate for removal
  Cooled-down:    consensus.maxIterations
  Armed watch:    consensus.maxIterations @ ARCHITECTURE
  Learning:       4 findings → /vibeflow:learning-loop-engine --mode consensus-history
  Cross-project:  consensus.maxIterations held in 3 projects  holdRate=0.67  (recommendation only)
  Recent:         CONFIG-TUNE — consensus.maxIterations 5 → 7
```

### Reading each line

- **Phase-runner** — the live/last `/vibeflow:phase-runner` walk from the
  Sprint-21 progress ledger: status, current step, convergence attempt
  `N/max`, and completed/total steps. `idle — no run` when no walk has
  happened.
- **Auto-apply** — applied/held/reverted tally over the last
  `loopAudit.window` rows. Per key, the **revert rate**; a key at
  `revertRate ≥ 0.5` is flagged **⚠ candidate for removal** from
  `autoApply.keys` (the same signal `meta-learning` raises).
- **Cooled-down** — keys that won't re-tune this sprint (a recent revert).
- **Armed watch** — a tune already applied, awaiting the next round's
  verdict (confirm or transactional-revert).
- **Learning** — how many slow-loop findings are waiting.
- **Cross-project** — *only when `globalLearning.enabled`* — keys that
  hold across multiple projects, with a cross-project hold rate. A
  **recommendation only**: `loop-status` never auto-allowlists; acting on
  it is the operator's call. See [CROSS-PROJECT-LEARNING.md](CROSS-PROJECT-LEARNING.md).
- **Recent** — the last few `learning-apply` decisions.

### Idle collapse

On a project that has never used the loop — no auto-apply, no cooldowns,
no armed watch, no learning report, **and** no phase-runner walk — the
dashboard collapses to one line:

```
Autonomous loop: idle (no activity).
```

## The written report

`/vibeflow:loop-status` also writes the same content to
**`.vibeflow/reports/loop-status.md`** — a durable, shareable "loop pane
of glass" with a project + phase + UTC-timestamp header. Read it without
re-running the skill; commit it to a PR; diff it across sprints.

## Read-only

`loop-status` **never** changes `vibeflow.config.json`, `autoApply.keys`,
or any source/artifact. Its only write is the report. Every flag and the
cross-project signal are *recommendations* — you apply them via
`/vibeflow:learning-apply` or by editing `autoApply.keys` yourself.

## See also

- [LOOP-AUDIT.md](LOOP-AUDIT.md) — the reader the dashboard renders.
- [AUTO-APPLY.md](AUTO-APPLY.md) — what produces the auto-apply telemetry.
- [META-LEARNING.md](META-LEARNING.md) — the revert-rate detector.
- [CROSS-PROJECT-LEARNING.md](CROSS-PROJECT-LEARNING.md) — the
  cross-project signal.
- `skills/phase-runner/SKILL.md` — the walk the phase-runner line tracks.
