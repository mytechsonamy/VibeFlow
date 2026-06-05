# Learning-Apply Lanes + Config-Key Map (Sprint 22)

`learning-apply` classifies each learning-loop finding into one of three
lanes. This file is the authoritative map the skill walks at Step 2-3.

## Lane 1 — config-tune

A recommendation is **config-tune** when it names one of these typed
`vibeflow.config.json` keys. The clamp range mirrors the Zod schema in
`mcp-servers/sdlc-engine/src/config.ts` — a tune is always bounded to the
range below (and additionally to ±`learningApply.maxRelativeStep` of the
current value for numerics).

| Key | Type | Schema range | Typical trigger |
|-----|------|--------------|-----------------|
| `consensus.maxIterations` | int | `[1, 20]` | `LEARNING-SLOW-CONVERGING-PHASE`, `LEARNING-CONVERGENCE-STALL` |
| `consensus.approvalThreshold` | float | `[0, 1]` | phases converging just under threshold |
| `consensus.excerptTokenBudget` | int | `[1000, 200000]` | reviewers missing context on large primaries |
| `consensus.excerptStrategy` | enum | `semantic \| headtail` | excerption noise |
| `reviewerMemory.maxEntriesPerArtifact` | int | `[1, 50]` | recurring criticals aging out too fast |
| `reviewerMemory.tokenBudget` | int | `[50, 5000]` | memory block truncated |
| `reviewerMemory.compaction` | enum | `theme-aware \| recency` | — |
| `phaseRunner.maxConvergenceAttempts` | int | `[1, 10]` | specialist-apply cycles exhausted |

**Numeric clamp algorithm:**

```
delta_cap = current * maxRelativeStep          # e.g. 5 * 0.5 = 2.5
proposed  = current ± min(requested_delta, delta_cap)
proposed  = clamp(proposed, schema_min, schema_max)
proposed  = round(proposed)                    # integers only
```

**Enum:** set to the recommended value verbatim; if it is not a legal
member of the enum, the finding falls through to **escalate**.

## Lane 2 — template-route

`LEARNING-RECURRING-SUGGESTION-THEME` findings (a theme across ≥3
distinct artifacts) are upstream artifact gaps, not config knobs. Map the
affected artifact's phase to its Sprint 17-E specialist:

| Phase | Specialist |
|-------|-----------|
| REQUIREMENTS | `prd-rewriter` |
| DESIGN | `design-spec-refiner` |
| ARCHITECTURE | `adr-author` |
| PLANNING | `test-strategy-refiner` |
| TESTING | `coverage-gap-filler` |
| DEPLOYMENT | `runbook-editor` |

With `learningApply.autoForkSpecialist` **false** (default),
`learning-apply` writes the `/vibeflow:consensus-specialist` dispatch
recommendation into the decisions report — recommend-only, the rewrite
stays operator-initiated (Sprint 22-C).

With `autoForkSpecialist` **true** (Sprint 27), it **auto-forks** the
matching specialist with a learning-fork brief
(`agents/_shared/learning-fork-brief.md`) → the specialist emits a
diff-first patch under `.vibeflow/state/patches/learning-fork-<ts>/`.
**Propose-only**: learning-apply never applies the patch — the operator
confirms via `/vibeflow:apply-arbiter-patch`.

## Lane 3 — escalate

Everything else: `LEARNING-REVIEWER-SKEW` (needs human calibration
judgement), ambiguous recommendations, enum recommendations with an
illegal value, or any finding that matches no config key. The decisions
report recommends `/vibeflow:decision-recommender` to frame the call.

## Safety invariants

- **Propose-only** — patches under `.vibeflow/state/patches/learning-<ts>/`
  + the decisions report are the only writes. `vibeflow.config.json`
  changes only via `--yes` + `git apply`.
- **Schema re-validation** — a patched config is parsed through
  `EngineConfigSchema` before apply; failure rejects the patch.
- **Evidence floor** — findings below `learningApply.minObservations`
  are skipped.
