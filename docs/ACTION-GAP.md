# Closing the Action Gap (Sprint 22)

VibeFlow's L3 slow loop has three stages. Before v2.10.0 only the first
two existed, leaving an **action gap** — the loop observed and framed,
but never acted.

```
  observe            frame                 act
┌───────────┐   ┌──────────────────┐   ┌───────────────┐
│ learning- │ → │ decision-        │ → │ learning-     │
│ loop-     │   │ recommender      │   │ apply         │
│ engine    │   │ (options +       │   │ (diff-first   │
│ (mines    │   │  trade-offs)     │   │  config patch │
│ history)  │   │                  │   │  + specialist │
└───────────┘   └──────────────────┘   │  routing)     │
 consensus-       decision-              └───────────────┘
 learning-        package.md              vibeflow.config
 report.md                                .json patch +
                                          decisions.md
```

## 1. Observe — `learning-loop-engine --mode consensus-history`

Mines `.vibeflow/state/consensus/history.jsonl` for patterns
(slow-converging phases, recurring suggestion themes, ineffective applied
themes, convergence stalls) and writes
`.vibeflow/reports/consensus-learning-report.md` with findings +
recommendations. See [LEARNING-LOOP.md](LEARNING-LOOP.md).

## 2. Frame — `decision-recommender` (optional)

Turns a finding into a decision package: problem statement, options with
trade-offs in both directions, a recommendation, and "do nothing" as
option zero. Use when a call needs framing before acting.

## 3. Act — `learning-apply` (Sprint 22)

Turns recommendations into **concrete, diff-first, operator-confirmed**
changes through three lanes:

- **config-tune** → a diff-first patch to `vibeflow.config.json`
  (e.g. raise `consensus.maxIterations`), bounded and clamped to the
  schema range, applied only with `--yes` after the patched config
  passes `EngineConfigSchema` re-validation.
- **template-route** → a recurring-theme finding becomes a
  `/vibeflow:consensus-specialist` dispatch recommendation (the operator
  initiates the rewrite — `learning-apply` does not auto-fork).
- **escalate** → hand to `decision-recommender` / the operator.

`learning-apply` is **propose-only**: it never writes
`vibeflow.config.json` or source directly — only patches under
`.vibeflow/state/patches/learning-<ts>/` and the audit report
`.vibeflow/reports/learning-apply-decisions.md`. See
[LEARNING-APPLY.md](LEARNING-APPLY.md).

## The full walk

```
/vibeflow:learning-loop-engine --mode consensus-history
  → consensus-learning-report.md  (finding: REQUIREMENTS needs 3 rounds ×4)
/vibeflow:learning-apply                 # preview
  → config-tune patch: consensus.maxIterations 5 → 7  (proposed, not applied)
  → template-route: missing-acceptance-criteria → prd-rewriter (recommended)
/vibeflow:learning-apply --yes           # apply the config patch
  → schema re-validation passes → git apply → maxIterations now 7
```

## Optional autonomy (Sprint 23)

By default the act stage is propose-only. A project that trusts the loop
can opt specific config keys into **bounded auto-apply**
(`learningApply.autoApply`): allowlisted tunes apply without a prompt,
snapshot the config first, and **auto-revert** if the next consensus
round regresses. Everything off the allowlist — and all source/template
changes — stays operator-confirmed. See [AUTO-APPLY.md](AUTO-APPLY.md).

## Why propose-only by default

The loop tunes the very machinery that governs quality gates. A
bounded-but-autonomous tuner that drifts `approvalThreshold` down over
sprints is exactly the "gate-suppression-creep" the learning loop is
meant to *catch*. Keeping a human in the loop on every config change
keeps the slow loop honest. Sprint 23 relaxes this *only* for
operator-allowlisted keys, and only with an auto-revert safety net — see
[AUTO-APPLY.md](AUTO-APPLY.md).
