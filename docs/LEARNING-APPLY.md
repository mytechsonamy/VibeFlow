# learning-apply — Operator Reference (Sprint 22)

`/vibeflow:learning-apply [--dry-run] [--yes]` turns
`learning-loop-engine` recommendations into concrete changes — safely.
It is the `consensus-arbiter` of the slow loop: **diff-first,
operator-confirmed, never writes config or source directly.**

## Invocation

| Form | Behaviour |
|------|-----------|
| `/vibeflow:learning-apply` | **Preview** (default): classify findings, write proposed patches + the decisions report, apply nothing. |
| `/vibeflow:learning-apply --dry-run` | Explicit alias for preview. |
| `/vibeflow:learning-apply --yes` | Apply the config-tune patches after the safety gates below. |

## The three lanes

| Lane | What it does |
|------|--------------|
| **config-tune** | Recommendation names a typed `vibeflow.config.json` key → a diff-first patch under `.vibeflow/state/patches/learning-<ts>/`. |
| **template-route** | A `recurring-suggestion-theme` → a `/vibeflow:consensus-specialist` dispatch recommendation (operator initiates). |
| **escalate** | Everything else → recommend `/vibeflow:decision-recommender`. |

The config-key map and per-field clamp ranges are in
`skills/learning-apply/references/lanes.md`.

## Safety gates

1. **Propose-only** — the only writes are patches +
   `.vibeflow/reports/learning-apply-decisions.md`. `vibeflow.config.json`
   changes only through `--yes` + `git apply`.
2. **Evidence floor** — findings below `learningApply.minObservations`
   (default 3) are skipped.
3. **Bounded** — a numeric tune moves at most
   `learningApply.maxRelativeStep` (default 0.5 = ±50%) from the current
   value, then is clamped to the field's schema range.
4. **Schema re-validation** — before `--yes` applies a patch, the patched
   config is parsed through the engine's `EngineConfigSchema`; an
   out-of-range or wrong-enum result is **rejected**, never applied.

## Configuration

```jsonc
// vibeflow.config.json
{
  "learningApply": {
    "enabled": true,         // kill switch (false ⇒ preview-only no-op)
    "maxRelativeStep": 0.5,  // cap on a single numeric tune (fraction)
    "minObservations": 3     // evidence floor a finding must clear
  }
}
```

All defaulted and partial-merge friendly
(`LearningApplyConfigSchema`, `mcp-servers/sdlc-engine/src/config.ts`).

## Outputs

- `.vibeflow/state/patches/learning-<ts>/NN-<key>.patch` + `manifest.json`
  — diff-first config patches (one per config-tune finding).
- `.vibeflow/reports/learning-apply-decisions.md` — per-finding audit
  (lane, target, rationale, observations, patch/dispatch, applied flag).

## See also

- [ACTION-GAP.md](ACTION-GAP.md) — the full observe → frame → act loop.
- [LEARNING-LOOP.md](LEARNING-LOOP.md) — the report this skill consumes.
