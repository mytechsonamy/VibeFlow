# Bounded Auto-Apply with Auto-Revert (Sprint 23)

Sprint 22's `learning-apply` is **propose-only**: it proposes config
patches, you confirm with `--yes`. Sprint 23 lets it go one step further
for tunes you trust — **auto-apply within strict guardrails** — without
giving up the safety that made propose-only the default.

> **Off by default.** `learningApply.autoApply.enabled` is `false`. A
> project that doesn't opt in behaves exactly as in v2.10.0 — every
> config change is operator-confirmed.

## How it works

When `autoApply.enabled` is true, a config-tune finding auto-applies
**only if its key is in the allowlist** `autoApply.keys` *and* it clears
every Sprint 22 gate (evidence floor, `maxRelativeStep` clamp,
`EngineConfigSchema` re-validation). The auto path skips none of those —
it only drops the operator prompt.

```
finding (config-tune)
  ├─ key ∈ autoApply.keys ?  ── no ──▶ propose-only (needs --yes)  [Sprint 22]
  │         │ yes
  ├─ clears minObservations + maxRelativeStep clamp + schema re-valid ?
  │         │ yes
  ├─ snapshot vibeflow.config.json  →  .vibeflow/state/auto-apply/<ts>/…bak
  ├─ git apply (no prompt)          →  Applied: auto
  └─ arm watch.json {key, baselineAgreement, phase, primaryArtifact, snapshot}
```

## Auto-revert on regression

Arming the watch lets the **next consensus round judge the tune**. The
`consensus-aggregator` hook — right after it finalises that round's
agreement — evaluates the watch:

- Same `{phase, primaryArtifact}` as the watch, and agreement dropped by
  more than `regressionDelta` below the baseline?
  → **restore the snapshot** (`vibeflow.config.json` back to its
  pre-change value), append an `auto-revert` row to `history.jsonl`, log
  to `.vibeflow/reports/auto-apply-reverts.md`, drop the watch, and
  **arm a cooldown** (`.vibeflow/state/auto-apply/cooldown-<key>`) so the
  key can't immediately re-tune and flap.
- Agreement held or improved?
  → the tune earned its place: drop the watch, log "AUTO-APPLY HELD".

The only config write the aggregator ever makes is a **restore to a
known-good snapshot** — bounded and auditable. With no watch armed (the
default), the aggregator is unchanged.

## Configuration

```jsonc
// vibeflow.config.json
{
  "learningApply": {
    "autoApply": {
      "enabled": false,             // master switch — OFF by default
      "keys": [],                   // allowlist; e.g. ["consensus.maxIterations"]
      "revertOnRegression": true,   // arm the auto-revert watch
      "regressionDelta": 0.05,      // next-round agreement drop > this ⇒ revert
      "demoteAfterReverts": 3,      // Sprint 24: lifetime self-demote threshold
      "transactional": true         // Sprint 24: atomic multi-key revert
    }
  }
}
```

Only keys in the Sprint 22 config-tune map
(`skills/learning-apply/references/lanes.md`) are eligible; listing any
other key is ignored. Source and templates **never** auto-apply.

## Safety model — five guardrails

1. **Default off** — opt-in per project.
2. **Allowlisted** — only `autoApply.keys` auto-apply; everything else
   stays operator-confirmed.
3. **Bounded + schema-validated** — the auto path reuses every Sprint 22
   gate; an out-of-range or invalid result is rejected, never applied.
4. **Snapshotted + auto-reverted** — every auto-apply is rolled back if
   the next round regresses.
5. **Cooldown** — a reverted key won't re-tune for the rest of the
   sprint, preventing flapping.

## Why this is safe to automate

The slow loop tunes the very machinery that governs quality gates. The
danger is a tuner that quietly drifts a gate looser over sprints — the
"gate-suppression-creep" the learning loop exists to *catch*. Auto-revert
is the answer: a tune that makes consensus *worse* is undone
automatically and cooled down, so the loop can only keep changes that
*improve* agreement. The operator still owns the allowlist (what may
auto-tune at all) and everything off it.

## Self-correcting (Sprint 24)

Auto-apply doesn't just revert bad tunes — it *learns* from them. Every
outcome (`auto-apply` → `auto-revert` | `auto-apply-held`) is recorded in
`history.jsonl`; the `learning-loop-engine` `auto-tune-ineffective`
detector flags keys that keep getting reverted, and `learning-apply`
self-demotes a chronically-reverted key to propose-only
(`demoteAfterReverts`). A multi-key run reverts as one
transaction (`transactional`). See [META-LEARNING.md](META-LEARNING.md).

## Seeing what auto-apply did

`/vibeflow:status` has an **Autonomous Loop** section (Sprint 25) that
consolidates every auto-apply outcome — applied/held/reverted tallies,
per-key revert rates, cooled-down keys, the armed watch, and pending
learning findings — into one view. See [LOOP-AUDIT.md](LOOP-AUDIT.md).

## See also

- [LEARNING-APPLY.md](LEARNING-APPLY.md) — the skill + its lanes.
- [ACTION-GAP.md](ACTION-GAP.md) — the full observe → frame → act loop.
- [META-LEARNING.md](META-LEARNING.md) — the self-correcting meta-loop.
- [LOOP-AUDIT.md](LOOP-AUDIT.md) — the autonomous-loop observability surface.
