# Sprint 23 — Bounded Auto-Apply with Auto-Revert (v2.11.0)

> ✅ **COMPLETE** — shipped v2.11.0 on 2026-06-04. All five tickets (S23-A..E) landed. Tests: sdlc-engine 176→179, hooks 139→149, new `sprint-23.sh` (43); total baseline 2514 → 2570 across 23 layers.

## Context

Sprint 22 shipped `learning-apply`: it turns learning-loop
recommendations into **diff-first, operator-confirmed**
`vibeflow.config.json` patches. It is deliberately **propose-only** —
nothing changes until the operator runs `--yes`. That was the right
first step, but it leaves the slow loop only half-autonomous: a team
that trusts the loop still has to babysit every routine config tune
(e.g. "REQUIREMENTS keeps needing 3 rounds → raise
`consensus.maxIterations`").

Sprint 23 closes that last gap **safely**: let `learning-apply`
auto-apply a tune — but only for config keys the operator has explicitly
**allowlisted**, only within the existing bounds, and with an
**auto-revert** that rolls the change back if the next consensus round
regresses. The framework stays propose-only by default (`autoApply` is
**off** unless opted in), so nothing about Sprint 22's safety posture
changes for anyone who doesn't turn it on.

User direction (this session): **bounded auto-apply** + **auto-apply with
auto-revert** (snapshot config before, auto-revert if the next round's
agreement regresses).

## Design Overview — four groups, five tickets

### Group 1 — Config: allowlist + auto-apply bounds (S23-A)

Extend `LearningApplyConfigSchema` (`config.ts`) with a nested
`autoApply` block — **default OFF**, so existing installs are unchanged:

```jsonc
"learningApply": {
  "enabled": true, "maxRelativeStep": 0.5, "minObservations": 3,
  "autoApply": {
    "enabled": false,            // master switch — default OFF (propose-only stays default)
    "keys": [],                  // allowlist: only these config keys may auto-apply
    "revertOnRegression": true,  // arm the auto-revert watch
    "regressionDelta": 0.05      // next-round agreement drop > this ⇒ revert
  }
}
```

- `keys` must be a subset of the Sprint 22 config-tune key map
  (`skills/learning-apply/references/lanes.md`); anything else stays
  propose-only even when `autoApply.enabled`.
- `regressionDelta ∈ [0, 1]`, `keys` is `string[]`.
- Unit tests: defaults (autoApply off + empty allowlist), partial-merge,
  range rejection (mirror S20-H/S21-E/S22-D).

### Group 2 — `learning-apply` auto-apply path (S23-B)

In `skills/learning-apply/SKILL.md`, add the auto-apply lane to Step 6.
When `autoApply.enabled` and a config-tune finding's **key ∈ allowlist**
AND it clears every existing gate (`minObservations`, `maxRelativeStep`
clamp, **`EngineConfigSchema` re-validation**):

1. **Snapshot** the current `vibeflow.config.json` to
   `.vibeflow/state/auto-apply/<ts>/vibeflow.config.json.bak` + record
   `{key, from, to, baselineAgreement, phase, primaryArtifact, appliedAt}`.
2. `git apply` the patch **without operator confirmation**.
3. Arm the revert watch: write `.vibeflow/state/auto-apply/watch.json`
   (the snapshot record above) so the aggregator can evaluate the next
   round (S23-C).
4. Audit in `learning-apply-decisions.md` as `Applied: auto` + the
   exact revert command + snapshot path.

A config-tune finding whose key is **not** allowlisted keeps the Sprint
22 behaviour exactly: diff-first patch, `Applied: false`, operator
confirms with `--yes`. `template-route` / `escalate` are unchanged.

- **Harness `[S23-B]`:** auto-apply-lane prose; allowlist gate (non-
  allowlisted key stays propose-only); snapshot-before-apply sentinel;
  watch.json write; `Applied: auto` audit prose; re-validation still
  gates the auto path.

### Group 3 — Auto-revert on regression (S23-C)

The revert trigger fires deterministically where agreement is already
computed: `consensus-aggregator.sh`, right after it appends the Sprint
20-A `history.jsonl` verdict row. Add a guarded **revert-watch**
evaluation:

- If `.vibeflow/state/auto-apply/watch.json` exists AND the just-
  finalised round is the **same phase + primaryArtifact** as the watch:
  - compute `delta = thisRound.agreement − watch.baselineAgreement`;
  - if `revertOnRegression` and `delta < −regressionDelta` → **restore**
    the snapshot (`cp` the `.bak` back over `vibeflow.config.json`),
    append a `auto-revert` row to `history.jsonl`, log to
    `.vibeflow/reports/auto-apply-reverts.md`, and **drop the watch**
    (+ a one-sprint cooldown marker for that key so it doesn't re-tune
    and flap);
  - else (agreement held or improved) → **confirm**: drop the watch,
    log "auto-apply held" (the tune earned its place).
- Reuses `vf_state_dir`; the only config write is a restore to a
  known-good snapshot (bounded, auditable). Fully guarded — does nothing
  when no watch is armed, so default behaviour is untouched.

- **Harness `[S23-C]`:** hook-test runtime — arm a watch with a high
  baseline, finalise a lower-agreement round → snapshot restored + watch
  dropped + revert logged; arm a watch, finalise a higher-agreement
  round → watch dropped, no restore; no watch → aggregator unchanged.

### Group 4 — Docs, harness, release (S23-D, S23-E)

**S23-D — docs + harness.**
- New `docs/AUTO-APPLY.md` (the bounded-auto-apply + auto-revert design,
  the default-off / allowlist / snapshot / cooldown safety model, config
  reference). Refresh `docs/LEARNING-APPLY.md` (the auto lane) +
  `docs/ACTION-GAP.md` (the loop is now optionally autonomous).
- `tests/integration/sprint-23.sh` — **≈70 assertions** across
  `[S23-A]..[S23-Z]` + self-audit `[S23-Z]` (config sentinels + skill
  prose + a config-schema runtime probe for the autoApply block).
- `hooks/tests/run.sh` — +≈5 for the S23-C revert-watch (restore /
  hold / no-watch).

**S23-E — v2.11.0 release.**
- `.claude-plugin/plugin.json` + `marketplace.json`: 2.10.0 → 2.11.0.
- `@vibeflow/sdlc-engine`: 1.8.0 → 1.9.0 (autoApply schema).
- `CHANGELOG.md` + `release-notes/2.11.0.md`; CLAUDE.md test counts +
  Sprint-23 ✅ COMPLETE; ROADMAP appendix row; mark `docs/SPRINT-23.md`
  COMPLETE; commit + tag `v2.11.0` + push.

## Files Touched (representative)

| Area | Files |
|---|---|
| Config (S23-A) | `mcp-servers/sdlc-engine/src/config.ts` (+ tests) |
| Auto-apply path (S23-B) | `skills/learning-apply/SKILL.md` (+ `references/lanes.md` allowlist note) |
| Auto-revert (S23-C) | `hooks/scripts/consensus-aggregator.sh` (+ `hooks/tests/run.sh`) |
| Docs/harness (S23-D) | `tests/integration/sprint-23.sh`, `docs/AUTO-APPLY.md`, `docs/LEARNING-APPLY.md`, `docs/ACTION-GAP.md` |
| Release (S23-E) | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `mcp-servers/sdlc-engine/package.json`, `CHANGELOG.md`, `release-notes/2.11.0.md`, `CLAUDE.md`, `ROADMAP.md` |

## Reused patterns (don't reinvent)

- **Bounds + schema re-validation gate** — Sprint 22 `learning-apply`
  Step 6 (the auto path reuses every gate; it only drops the operator
  prompt for allowlisted keys).
- **history.jsonl append + agreement curve** — `consensus-aggregator.sh`
  (S20-A) is where the revert watch reads agreement.
- **Snapshot/restore via cp + audit md** — same shape as
  `apply-arbiter-patch` revert guidance.
- **Typed config defaulted + partial-merge** — `config.ts`
  `LearningApplyConfigSchema` (S22-D), now nesting `autoApply`.

## Verification (merge-green gate)

| Layer | Before (v2.10.0) | After (v2.11.0, target) | Delta |
|---|---|---|---|
| `sdlc-engine` unit | 176 | ~180 | +≈4 (autoApply schema) |
| `hooks/tests/run.sh` | 139 | ~144 | +≈5 (revert-watch restore/hold/no-watch) |
| `tests/integration/run.sh` | 399 | 399 | 0 |
| Sprint-*.sh bundle | ~1814 | ~1884 | +≈70 (sprint-23.sh) |
| **Total** | **2514** | **~2593** | **+≈79** |

Run with `env -u VF_ALLOW_PHASE_WRITE`: 5 MCP `npm test`,
`bash hooks/tests/run.sh`, `bash tests/integration/run.sh`,
`bash tests/integration/sprint-23.sh`. Rebuild `sdlc-engine` dist after
the config change.

**E2E walk:** set `learningApply.autoApply = {enabled:true,
keys:["consensus.maxIterations"], revertOnRegression:true,
regressionDelta:0.05}`; seed a slow-converging-phase finding; run
`learning-apply`; confirm (1) `maxIterations` is auto-applied (snapshot
written, `watch.json` armed, `Applied: auto`), (2) a non-allowlisted
key in the same report stays propose-only, (3) finalise a next round
with lower agreement → config restored from snapshot + revert logged +
watch dropped, (4) re-run with a higher-agreement round → watch dropped,
no restore, (5) `autoApply.enabled:false` (default) ⇒ everything stays
propose-only exactly as in v2.10.0.

## Out of Scope (→ Sprint 24+)

- **Auto-applying source/template changes.** Auto-apply is config-keys
  only; template fixes stay operator-initiated via the phase specialists
  (Sprint 22-C routing).
- **Auto-forking the phase specialist** (Sprint 22 deferral, unchanged).
- **Embedding-based excerption / memory** (S21 deferral, unchanged).
- **Multi-key transactional revert** (revert a *set* of tunes as one
  unit). Sprint 23 watches one armed key at a time; the cooldown
  prevents overlap.
