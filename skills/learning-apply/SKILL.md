---
name: learning-apply
description: Closes the L3 action gap — turns learning-loop-engine recommendations into concrete, diff-first, operator-confirmed changes. Reads .vibeflow/reports/consensus-learning-report.md and classifies each finding into three lanes — config-tune (diff-first patch to vibeflow.config.json), template-route (recommend the matching phase specialist), escalate (hand to decision-recommender). Propose-only by default — config patches apply only with --yes after EngineConfigSchema re-validation + bounds clamp. Sprint 23 adds opt-in bounded auto-apply (learningApply.autoApply, default OFF): allowlisted config keys auto-apply with a pre-change snapshot + an auto-revert watch that rolls back if the next consensus round regresses. Invoke as /vibeflow:learning-apply [--dry-run] [--yes].
allowed-tools: Read Write Grep Glob Bash(jq *) Bash(mkdir *) Bash(rm *) Bash(node *) Bash(git apply *) Bash(cp *) Bash(mv *)
context: fork
---

# Learning Apply

An L3 Truth-Evolution skill. Where `learning-loop-engine` *observes*
(produces recommendations) and `decision-recommender` *frames* (options +
trade-offs), `learning-apply` *acts* — but safely. It is the
`consensus-arbiter` of the slow loop: it converts recommendations into
**diff-first patches the operator confirms**, and it **never writes
`vibeflow.config.json` or source files directly**. Its only writes are to
`.vibeflow/state/patches/**` and `.vibeflow/reports/learning-apply-decisions.md`.

## When You're Invoked

- **On demand** as `/vibeflow:learning-apply [--dry-run] [--yes]`,
  typically right after `learning-loop-engine --mode consensus-history`.
- **From `decision-recommender`** once a decision package has framed a
  config-tuning or template decision and the operator wants to enact it.

Default (no flag) = **preview**: classify, propose patches, write the
decisions report, apply nothing. `--yes` applies the config patches after
the safety gates below. `--dry-run` is an explicit alias for preview.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| `.vibeflow/reports/consensus-learning-report.md` | yes | From `learning-loop-engine --mode consensus-history` (Sprint 20-B/C). Each finding carries `{patternId, recommendation, observations, affectedArtifacts}`. |
| `.vibeflow/reports/learning-report.md` | optional | The other learning modes; same finding shape. |
| `vibeflow.config.json` | yes | The tuning target + the current values bounds are computed against. Missing ⇒ emit "run /vibeflow:init" and stop. |
| `learningApply.*` config | optional | `{enabled, maxRelativeStep (0.5), minObservations (3), autoApply}`. `enabled:false` ⇒ no-op preview. `autoApply` (Sprint 23, default `{enabled:false, keys:[], revertOnRegression:true, regressionDelta:0.05}`) opts allowlisted keys into bounded auto-apply (Step 7). |

## Step 1 — Read the report + config

```bash
REPORT=".vibeflow/reports/consensus-learning-report.md"
[ -f "$REPORT" ] || { echo "learning-apply: no consensus-learning-report.md — run /vibeflow:learning-loop-engine --mode consensus-history first"; exit 0; }
[ -f vibeflow.config.json ] || { echo "learning-apply needs vibeflow.config.json — run /vibeflow:init"; exit 1; }
ENABLED="$(jq -r '.learningApply.enabled // true' vibeflow.config.json)"
MAX_STEP="$(jq -r '.learningApply.maxRelativeStep // 0.5' vibeflow.config.json)"
MIN_OBS="$(jq -r '.learningApply.minObservations // 3' vibeflow.config.json)"
[ "$ENABLED" = "false" ] && { echo "learning-apply disabled (learningApply.enabled=false) — preview only"; }
```

Parse the report's findings (each has a `Pattern:` / `Observations:` /
`Recommendation:` block). **Skip any finding with
`observations < minObservations`** — the evidence floor is the same one
the learning loop applied; we never act on a coincidence.

## Step 2 — Classify each finding into a lane

| Lane | Trigger | Action |
|------|---------|--------|
| **config-tune** | the recommendation names a typed config key (see `references/lanes.md` for the full map): `consensus.maxIterations`, `consensus.approvalThreshold`, `consensus.excerptStrategy`, `consensus.excerptTokenBudget`, `reviewerMemory.compaction`, `reviewerMemory.maxEntriesPerArtifact`, `phaseRunner.maxConvergenceAttempts`, … | Step 3 — diff-first config patch |
| **template-route** | a `LEARNING-RECURRING-SUGGESTION-THEME` finding (a theme across ≥3 artifacts → an upstream template/convention gap) | Step 4 — phase-specialist dispatch recommendation |
| **escalate** | anything else (ambiguous, needs human judgement, `reviewer-skew`) | record in the decisions report; recommend `/vibeflow:decision-recommender` |

A finding that matches no lane is **escalate**, never silently dropped.

## Step 3 — config-tune: emit a diff-first patch (propose-only)

For each config-tune finding:

1. Resolve the target key + the recommended direction/value from the
   recommendation text.
2. Compute the proposed value, **bounded**:
   - **numeric** — move at most `maxRelativeStep` (fraction) from the
     current value, then **clamp to the field's schema range** (see
     `references/lanes.md`; e.g. `maxIterations ∈ [1,20]`,
     `approvalThreshold ∈ [0,1]`). Round integers.
   - **enum** — set to the recommended value verbatim (must be a legal
     enum member, else → escalate).
3. Produce a `git apply`-compatible patch to `vibeflow.config.json`
   (`--- a/vibeflow.config.json`, `+++ b/vibeflow.config.json`, `@@`
   hunks) under `.vibeflow/state/patches/learning-<ts>/NN-<key>.patch`,
   plus a `manifest.json`:

```json
{ "session": "learning-<ts>", "generatedAt": "<ISO>",
  "apply": [ { "file": "01-consensus.maxIterations.patch",
               "key": "consensus.maxIterations",
               "from": 5, "to": 7, "finding": "LEARNING-SLOW-CONVERGING-PHASE" } ] }
```

**Never edit `vibeflow.config.json` here.** Only the patch + manifest are
written. (Same posture as `consensus-arbiter`.)

## Step 4 — template-route: recommend the phase specialist (S22-C)

A `recurring-suggestion-theme` is an upstream artifact gap — the fix is a
rewrite, not a config knob. Map the affected artifact's phase to its
specialist via the Sprint 17-E `consensus-specialist` table:

| Phase | Specialist |
|-------|-----------|
| REQUIREMENTS | `prd-rewriter` |
| DESIGN | `design-spec-refiner` |
| ARCHITECTURE | `adr-author` |
| PLANNING | `test-strategy-refiner` |
| TESTING | `coverage-gap-filler` |
| DEPLOYMENT | `runbook-editor` |

Write a **dispatch recommendation** into the decisions report — the
`/vibeflow:consensus-specialist` invocation the operator should run on
the affected artifact. `learning-apply` **does NOT fork the specialist
itself**: the deep rewrite stays operator-initiated (propose-only).

## Step 5 — Write the decisions report

`.vibeflow/reports/learning-apply-decisions.md` — one entry per finding:

```markdown
## CONFIG-TUNE — consensus.maxIterations 5 → 7
- Finding: LEARNING-SLOW-CONVERGING-PHASE (observations: 4)
- Rationale: REQUIREMENTS reached APPROVED in round >1 across 4 sessions
- Bounds: +40% (≤ maxRelativeStep 0.5), clamped to [1,20] → 7
- Patch: .vibeflow/state/patches/learning-<ts>/01-consensus.maxIterations.patch
- Applied: false   (flips to true on --yes)

## TEMPLATE-ROUTE — missing-acceptance-criteria (×4 PRDs)
- Recommended: /vibeflow:consensus-specialist  (REQUIREMENTS → prd-rewriter)
- learning-apply does not auto-fork; operator initiates the rewrite.

## ESCALATE — reviewer-skew (codex 68% of criticals)
- Recommended: /vibeflow:decision-recommender (needs human judgement)
```

## Step 6 — Apply (only with `--yes`)

Preview is the default. With `--yes`, for each config-tune patch:

1. **Preview** the diff to the operator.
2. **Schema re-validation gate.** Apply the patch to a *copy* and run the
   result through the engine's `EngineConfigSchema`:

```bash
cp vibeflow.config.json /tmp/vf-cfg-check.json
git apply --include=vibeflow.config.json "<patch>"  # to a worktree copy / staged check
node -e 'const {EngineConfigSchema}=require("./mcp-servers/sdlc-engine/dist/config.js");
  const raw=require("/tmp/vf-cfg-check.json");
  const r=EngineConfigSchema.safeParse({project:raw.project||"p", ...raw});
  process.exit(r.success?0:1)'
```

   If the patched config **fails** schema validation (out-of-range, wrong
   enum), **reject** the patch — never apply an invalid config. The typed
   schema (`config.ts`) is the safety net.
3. On pass, `git apply` the patch to `vibeflow.config.json` and flip
   `Applied: true` in the decisions report.

A patch that the operator declines, or that fails re-validation, leaves
`vibeflow.config.json` untouched.

## Step 7 — Bounded auto-apply (opt-in, Sprint 23)

**Off by default.** When `learningApply.autoApply.enabled` is true, a
config-tune patch may apply **without operator confirmation** — but
*only* if its key is in the `autoApply.keys` allowlist. This runs on a
normal `/vibeflow:learning-apply` invocation (no `--yes` needed for
allowlisted keys); a key **not** in the allowlist always falls back to
the Step 6 operator-confirmed path.

```bash
AUTO_ON="$(jq -r '.learningApply.autoApply.enabled // false' vibeflow.config.json)"
mapfile -t AUTO_KEYS < <(jq -r '.learningApply.autoApply.keys[]? // empty' vibeflow.config.json)
REGRESS="$(jq -r '.learningApply.autoApply.regressionDelta // 0.05' vibeflow.config.json)"
```

For each config-tune patch whose `key ∈ AUTO_KEYS` that has **already
cleared every Step 1-6 gate** (`minObservations`, `maxRelativeStep`
clamp, **`EngineConfigSchema` re-validation** — the auto path skips
*none* of them):

1. **Snapshot** the current config + record the baseline agreement (the
   pre-change agreement for this phase + primary from
   `history.jsonl`, used by the auto-revert watch):

```bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; SNAP=".vibeflow/state/auto-apply/$TS"
mkdir -p "$SNAP"; cp vibeflow.config.json "$SNAP/vibeflow.config.json.bak"
BASE_AGREE="$(jq -s 'map(select(.type=="verdict" and .primaryArtifact==$p and .phase==$ph))
  | (sort_by(.recordedAt) | last.agreement) // 0' \
  --arg p "$PRIMARY" --arg ph "$PHASE" .vibeflow/state/consensus/history.jsonl 2>/dev/null || echo 0)"
```

2. `git apply` the patch to `vibeflow.config.json` (no prompt).
3. **Arm the revert watch** so the aggregator evaluates the next round:

```bash
jq -n -c --arg key "$KEY" --argjson from "$FROM" --argjson to "$TO" \
  --arg phase "$PHASE" --arg primary "$PRIMARY" \
  --argjson baseline "$BASE_AGREE" --argjson delta "$REGRESS" \
  --arg snap "$SNAP/vibeflow.config.json.bak" --arg ts "$TS" \
  '{key:$key, from:$from, to:$to, phase:$phase, primaryArtifact:$primary,
    baselineAgreement:$baseline, regressionDelta:$delta,
    snapshot:$snap, appliedAt:$ts}' \
  > .vibeflow/state/auto-apply/watch.json
```

4. Audit in `learning-apply-decisions.md` as `Applied: auto` + the
   revert command (`cp "$SNAP/vibeflow.config.json.bak" vibeflow.config.json`)
   + the snapshot path.

A key with an active **cooldown marker** (`.vibeflow/state/auto-apply/cooldown-<key>`,
written by the aggregator after an auto-revert — Sprint 23-C) is
**skipped** for the rest of the sprint and stays propose-only, so a
reverted tune never immediately re-applies and flaps.

## Gate Contract

1. **Propose-only by default.** With `autoApply.enabled` false (the
   default), `learning-apply` never writes `vibeflow.config.json` or any
   source directly — only patches + the decisions report; config changes
   land solely through `--yes` + `git apply`.
2. **Bounded.** Every numeric tune moves ≤ `maxRelativeStep` and is
   clamped to the field's schema range; findings below
   `minObservations` are skipped.
3. **Schema-validated.** A patched config that fails `EngineConfigSchema`
   is rejected, never applied — including the auto-apply path.
4. **Allowlisted auto-apply only.** Auto-apply (Step 7) touches *only*
   keys in `autoApply.keys`, snapshots before applying, and arms an
   auto-revert watch; a reverted key is cooled-down so it can't flap.
   Source/template changes never auto-apply.
5. **No auto-fork.** Template-route findings are *recommended* to a phase
   specialist; the operator initiates the rewrite.

## Non-Goals

- **No unbounded auto-apply.** Auto-apply (Sprint 23) is opt-in
  (`autoApply.enabled`, default off), allowlisted, snapshotted, and
  auto-reverted on regression. It never touches non-allowlisted keys,
  source, or templates. See `docs/AUTO-APPLY.md`.
- **No template rewriting** — that's the phase specialists' job;
  learning-apply only routes to them.

## See also

- `docs/ACTION-GAP.md` — the full learning → decide → apply loop
- `docs/LEARNING-APPLY.md` — operator reference (lanes, flags, bounds)
- `references/lanes.md` — config-key map + per-field bounds
- `skills/consensus-arbiter/SKILL.md` — the diff-first pattern reused here
- `skills/apply-arbiter-patch/SKILL.md` — the preview/`--yes` apply pattern
