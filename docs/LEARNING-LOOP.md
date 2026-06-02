# The Learning Loop — Consensus History Mining (Sprint 20)

VibeFlow's **fast loop** (consensus-orchestrator) answers one question per
run: *is this artifact ready to leave its phase right now?* The **slow
loop** — the L3 Truth-Evolution layer — asks a different question across
*time*: *what does our review history tell us about how we get there?*

Sprint 20 wires the slow loop to the consensus telemetry that has been
accumulating on disk since Sprint 17 but that nothing read until now.

## What gets recorded

Every finalised consensus round appends one **verdict row** to the
cross-session roll-up `.vibeflow/state/consensus/history.jsonl`
(written by `consensus-aggregator.sh`):

```json
{
  "type": "verdict",
  "sessionId": "…",
  "phase": "REQUIREMENTS",
  "primaryArtifact": "docs/PRD.md",
  "round": 2,
  "status": "NEEDS_REVISION",
  "agreement": 0.78,
  "counts": { "approved": 1, "needsRevision": 2, "rejected": 0, "critical": 2 },
  "reviewers": [ { "name": "codex", "verdict": "NEEDS_REVISION", "critical": 1 } ],
  "suggestionThemes": ["ambiguity", "missing-acceptance-criteria"],
  "timeout": false,
  "recordedAt": "…"
}
```

Each `apply-arbiter-patch` run appends an **arbiter-decision row**:

```json
{ "type": "arbiter-decision", "sessionId": "…", "round": 2,
  "applied": ["docs/PRD.md"], "rejected": [], "recordedAt": "…" }
```

The roll-up is **append-only** and **idempotent**: re-finalising the same
`{sessionId, round}` replaces that row rather than duplicating it.

## Mining it: `learning-loop-engine --mode consensus-history`

The fourth mode of `learning-loop-engine` (alongside `test-history`,
`production-feedback`, `drift-analysis`) reads the roll-up over a sprint
window (`--sprint N`, default `learningLoop.sprintWindow = 3`) and emits
`.vibeflow/reports/consensus-learning-report.md`.

Every pattern must clear the universal **≥ 3-observation floor**
(`learningLoop.minObservations`), so a one-off never becomes a
recommendation:

| Pattern | Signature | Why it matters |
|---|---|---|
| `slow-converging-phase` | ≥ 3 sessions in a phase need `round > 1` to reach APPROVED | The phase keeps admitting low-quality artifacts; the cost is paid every sprint |
| `reviewer-skew` | one reviewer holds > 60% of criticals across the window | Bus-factor risk or mis-calibration — worth knowing, never auto-silenced |
| `recurring-suggestion-theme` | the same theme recurs across ≥ 3 distinct artifacts | A systemic upstream gap (template/convention), not a per-artifact slip |
| `convergence-stall` | ≥ 3 stall events (`convergence-stalled.md` / `max-iterations-reached.md`) | The iteration loop is grinding without converging |
| `primary-artifact-churn` | one artifact consumes an outlier number of rounds | The artifact is under-specified or contested |
| `ineffective-theme` | a theme `applied` at round R is followed by agreement delta ≤ 0.02, ≥ 3 times | **Wasted-effort signal** — applying this kind of fix never moves the needle (S20-C) |

### The effectiveness trace (S20-C)

The `ineffective-theme` detector joins each `arbiter-decision` row against
the *next* round's `verdict` row for the same session and computes:

```
delta = verdict[round+1].agreement − verdict[round].agreement
```

When a theme is applied but agreement stays flat across ≥ 3 occurrences,
the loop stops recommending it — the real objection is elsewhere, and
grinding on cosmetic patches just burns reviewer rounds. Themes with a
consistently positive delta are surfaced as *reliably-converging* in the
report appendix.

## Feeding decisions

`decision-recommender` consumes `consensus-learning-report.md` as a
first-class findings source (Sprint 20-G). A `slow-converging-phase` or
`convergence-stall` finding that recommends a `consensus.*` change is
auto-detected as a `gate-adjustment` decision type — framing "raise
`consensus.maxIterations` vs tighten the PRD template vs escalate to a
specialist" as an explicit options trade-off, with "do nothing" always as
option zero.

## Acting on the report (Sprint 22)

`decision-recommender` *frames* the findings; **`learning-apply`** *acts*
on them — diff-first and operator-confirmed. It classifies each finding
into config-tune (a `vibeflow.config.json` patch), template-route (a
phase-specialist dispatch recommendation), or escalate, and never writes
config or source directly. This closes the action gap: a
`slow-converging-phase` finding becomes a proposed
`consensus.maxIterations` bump you confirm with `--yes`. See
[LEARNING-APPLY.md](LEARNING-APPLY.md) and [ACTION-GAP.md](ACTION-GAP.md).

## Configuration

```jsonc
// vibeflow.config.json
{
  "learningLoop": {
    "enabled": true,        // kill switch
    "sprintWindow": 3,      // default look-back when --sprint is absent
    "minObservations": 3    // evidence floor per pattern (≥ 1)
  }
}
```

All fields are optional; partial objects pick up the defaults above
(`LearningLoopConfigSchema`, `mcp-servers/sdlc-engine/src/config.ts`).

## See also

- [REVIEWER-MEMORY.md](REVIEWER-MEMORY.md) — the other half of the slow
  loop: reviewers remembering what they already raised.
- [CONSENSUS-FLOW.md](CONSENSUS-FLOW.md) — where the history rows are
  written in the consensus flow.
- [CONSENSUS-ITERATION.md](CONSENSUS-ITERATION.md) — the round loop that
  produces the agreement curve the slow loop mines.
