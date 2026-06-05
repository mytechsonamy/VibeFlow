# Autonomous-Loop Audit (Sprint 25)

By Sprint 24 the slow loop was deeply autonomous — but its activity was
scattered across six files. Sprint 25 adds a single pane of glass: a
read-only **audit reader** that consolidates the telemetry, surfaced as
the **Autonomous Loop** section of `/vibeflow:status`.

## The reader

`hooks/scripts/loop-audit.sh` is read-only and fully guarded (every
absent file degrades to zeros/empties, so a fresh project never errors).
It reads:

| Source | Contributes |
|---|---|
| `.vibeflow/state/consensus/history.jsonl` | per-key `auto-apply` / `auto-revert` / `auto-apply-held` counts (last `loopAudit.window` rows) |
| `.vibeflow/state/auto-apply/cooldown-*` | currently cooled-down keys |
| `.vibeflow/state/auto-apply/watch.json` | the armed watch (a tune awaiting next-round judgement) |
| `.vibeflow/reports/consensus-learning-report.md` | learning finding count |
| `.vibeflow/reports/learning-apply-decisions.md` | recent decisions |
| `.vibeflow/state/phase-runner-progress.json` | the live/last phase-runner walk (Sprint 30-A) |
| `$(vf_global_dir)/global-learning.jsonl` | cross-project signal, when `globalLearning.enabled` (Sprint 30-A) |

…and emits one compact JSON document:

```json
{
  "autoApply": {
    "applied": 3, "reverted": 2, "held": 1,
    "armedWatch": { "keys": ["consensus.maxIterations"], "phase": "…", "primaryArtifact": "…" },
    "cooldowns": ["consensus.maxIterations"]
  },
  "perKey": [
    { "key": "consensus.maxIterations", "applied": 3, "reverted": 2, "held": 1, "revertRate": 0.67, "cooledDown": true }
  ],
  "learning": { "reportExists": true, "findingCount": 4 },
  "recentDecisions": ["CONFIG-TUNE — consensus.maxIterations 5 → 7"],
  "phaseRunner": {
    "phase": "TESTING", "status": "running", "currentStep": "consensus-round-1",
    "attempt": 2, "maxConvergenceAttempts": 3, "stepsDone": 1, "stepsTotal": 2
  },
  "crossProject": {
    "distinctProjects": 3,
    "perKey": [ { "key": "consensus.maxIterations", "projects": 3, "holdRate": 0.67 } ]
  }
}
```

`phaseRunner` is `null` when no phase-runner walk has run;
`crossProject` is `null` unless `globalLearning.enabled` *and* a
`global-learning.jsonl` exists. Both were added in **Sprint 30-A** to feed
the dedicated `/vibeflow:loop-status` dashboard — `/vibeflow:status`'
Autonomous Loop section ignores them and is byte-for-byte unchanged.

## Reading the signals

`/vibeflow:status` → **Autonomous Loop** renders this as:

- **Auto-apply tally + per-key revert rate.** A key with
  `revertRate ≥ 0.5` is flagged *"candidate for removal from
  `autoApply.keys`"* — the same signal the S24-B `auto-tune-ineffective`
  detector raises, visible at a glance.
- **Cooled-down keys** — won't re-tune this sprint (a recent revert).
- **Armed watch** — a tune already applied, awaiting the next round's
  verdict to be confirmed or reverted.
- **Learning report** — how many findings are waiting; read them with
  `/vibeflow:learning-loop-engine --mode consensus-history`.
- **Recent decisions** — the last few `learning-apply` actions.

When nothing has happened (auto-apply never enabled, no markers, no
report), the section collapses to a single idle line — no noise for
projects that don't use the autonomous loop.

## Configuration

```jsonc
{ "loopAudit": { "window": 20 } }
```

`window` bounds how many recent `auto-*` rows the per-key tally
summarizes (`int [1, 1000]`, default 20) — so the audit reflects *recent*
behaviour, not the whole project lifetime.

## Two surfaces

The reader feeds **two** surfaces:

- **`/vibeflow:status`** → Autonomous Loop section — a *quick inline
  glance* using `autoApply` / `perKey` / `learning` / `recentDecisions`.
- **`/vibeflow:loop-status`** (Sprint 30-B) → the *full dashboard* — uses
  every field, including `phaseRunner` + `crossProject`, and writes a
  durable `.vibeflow/reports/loop-status.md` audit. See
  [LOOP-STATUS.md](LOOP-STATUS.md).

## See also

- [LOOP-STATUS.md](LOOP-STATUS.md) — the dedicated dashboard this reader feeds.
- [AUTO-APPLY.md](AUTO-APPLY.md) — what produces the auto-apply telemetry.
- [META-LEARNING.md](META-LEARNING.md) — the detector behind the
  revert-rate flag.
- [CROSS-PROJECT-LEARNING.md](CROSS-PROJECT-LEARNING.md) — the
  `crossProject` signal's source.
