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

Behaviour depends on `learningApply.autoForkSpecialist` (Sprint 27-A,
default **false**):

```bash
AUTO_FORK="$(jq -r '.learningApply.autoForkSpecialist // false' vibeflow.config.json)"
```

**`autoForkSpecialist` false (default) — recommend-only.** Write a
**dispatch recommendation** into the decisions report: the
`/vibeflow:consensus-specialist` invocation the operator should run on
the affected artifact. `learning-apply` does NOT fork the specialist;
the deep rewrite stays operator-initiated (the Sprint 22-C behaviour).

**`autoForkSpecialist` true — propose-only auto-fork (Sprint 27-B).**
Automatically fork the matching phase specialist, but **never apply** its
patch — the operator still confirms via `apply-arbiter-patch`. For each
`recurring-suggestion-theme` finding that clears `minObservations`:

1. **Write a learning-fork brief** so the specialist knows what to fix
   (it normally reads a consensus session; here the brief stands in):

```bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; FORK=".vibeflow/state/patches/learning-fork-$TS"
mkdir -p "$FORK"
cat > "$FORK/brief.md" <<EOF
# Learning-Fork Brief (Sprint 27)
- theme: <recurring suggestion theme title>
- primaryArtifact: <affected artifact path>
- seenCount: <how many artifacts/sprints the theme recurred across>
- rationale: <one line — why this is a systemic gap, not a one-off>
- evidence: .vibeflow/reports/consensus-learning-report.md
Treat the theme as the structural gap to resolve in primaryArtifact.
Emit ONE diff-first patch under this directory. Do NOT write source.
EOF
```

2. **Fork the matching phase specialist** (per the table above /
   `references/lanes.md`) pointing it at `$FORK/brief.md` + the artifact.
   The specialist emits its diff-first patch into `$FORK/` exactly as it
   would from a consensus session — **never writing the artifact
   directly** (its Sprint 17-D contract is unchanged; see
   `agents/_shared/learning-fork-brief.md`).

3. **Record + stop.** In the decisions report:
   `Specialist forked: <agent> on <artifact> → patch at $FORK/; apply
   with /vibeflow:apply-arbiter-patch`. **learning-apply NEVER applies
   the patch** — propose-only holds for templates exactly as it does for
   non-allowlisted config keys.

Guardrails: one fork per theme per run; honours `learningApply.enabled`;
auto-fork is **template-route only** — config-tune and escalate lanes are
unchanged.

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
DEMOTE_AT="$(jq -r '.learningApply.autoApply.demoteAfterReverts // 3' vibeflow.config.json)"  # Sprint 24-C
TRANSACTIONAL="$(jq -r '.learningApply.autoApply.transactional // true' vibeflow.config.json)" # Sprint 24-D
```

**Self-demote on chronic reverts (Sprint 24-C).** Before auto-applying
an allowlisted `KEY`, count its `auto-revert` rows in `history.jsonl`. A
key reverted `≥ demoteAfterReverts` times doesn't respond to tuning — it
is **demoted to propose-only for this run even though it stays
allowlisted** (a longer-horizon guard than the per-sprint cooldown):

```bash
REVERTS="$(jq -s --arg k "$KEY" 'map(select(.type=="auto-revert" and .key==$k)) | length' \
  .vibeflow/state/consensus/history.jsonl 2>/dev/null || echo 0)"
if (( REVERTS >= DEMOTE_AT )); then
  # Record `Applied: demoted (N reverts ≥ threshold) — proposing instead`
  # and route KEY through the Step 6 propose-only path. Do NOT auto-apply.
  continue
fi
```

Eligible keys are the allowlisted ones that cleared **every Step 1-6
gate** (`minObservations`, `maxRelativeStep` clamp, **`EngineConfigSchema`
re-validation** — the auto path skips *none*) and are **not** demoted
and **not** cooled-down.

**Transactional batch (Sprint 24-D).** With `transactional` true
(default), take **one** pre-batch snapshot, apply **all** eligible keys,
and arm **one** watch over the whole set so they revert/hold as a unit:

```bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; SNAP=".vibeflow/state/auto-apply/$TS"
mkdir -p "$SNAP"; cp vibeflow.config.json "$SNAP/vibeflow.config.json.bak"   # ONE snapshot
BASE_AGREE="$(jq -s 'map(select(.type=="verdict" and .primaryArtifact==$p and .phase==$ph))
  | (sort_by(.recordedAt) | last.agreement) // 0' \
  --arg p "$PRIMARY" --arg ph "$PHASE" .vibeflow/state/consensus/history.jsonl 2>/dev/null || echo 0)"

for KEY in "${ELIGIBLE[@]}"; do
  git apply "$SNAP/../patches/.../$KEY.patch"   # apply each eligible tune, no prompt
  # Sprint 24-A: record the auto-apply outcome so the meta-learning
  # detector (S24-B) can compute a per-key revert rate.
  jq -n -c --arg key "$KEY" --arg phase "$PHASE" --arg primary "$PRIMARY" --arg ts "$TS" \
    '{type:"auto-apply", key:$key, phase:$phase, primaryArtifact:$primary, appliedAt:$ts}' \
    >> .vibeflow/state/consensus/history.jsonl
done

# ONE watch over the whole transaction (keys[] — the aggregator reverts
# the set atomically by restoring this one snapshot, Sprint 24-D).
jq -n -c --argjson keys "$(printf '%s\n' "${ELIGIBLE[@]}" | jq -R . | jq -s .)" \
  --arg phase "$PHASE" --arg primary "$PRIMARY" \
  --argjson baseline "$BASE_AGREE" --argjson delta "$REGRESS" \
  --arg snap "$SNAP/vibeflow.config.json.bak" --arg ts "$TS" \
  '{keys:$keys, key:($keys[0] // "unknown"), phase:$phase, primaryArtifact:$primary,
    baselineAgreement:$baseline, regressionDelta:$delta, snapshot:$snap, appliedAt:$ts}' \
  > .vibeflow/state/auto-apply/watch.json
```

With `transactional` false, fall back to the Sprint-23 one-key-at-a-time
flow (one snapshot + one single-`key` watch per applied key).

Audit each applied key in `learning-apply-decisions.md` as
`Applied: auto` + the revert command
(`cp "$SNAP/vibeflow.config.json.bak" vibeflow.config.json`) + snapshot path.

A key with an active **cooldown marker** (`.vibeflow/state/auto-apply/cooldown-<key>`,
written by the aggregator after an auto-revert — Sprint 23-C) is
**skipped** for the rest of the sprint and stays propose-only, so a
reverted tune never immediately re-applies and flaps. The Sprint 24-C
self-demote is the *long-horizon* counterpart: cooldown is per-sprint;
self-demote fires whenever the key's lifetime revert count crosses
`demoteAfterReverts`, so a key that simply doesn't respond to tuning
stops auto-applying for good (and the `auto-tune-ineffective` detector
recommends removing it from the allowlist — `docs/META-LEARNING.md`).

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
- **No template rewriting by learning-apply itself** — the phase
  specialists do the rewrite. learning-apply routes to them (recommend),
  or with `autoForkSpecialist` *forks* them (Sprint 27) — but the
  resulting diff-first patch is **always operator-confirmed via
  apply-arbiter-patch**. learning-apply never applies a template patch.

## See also

- `docs/ACTION-GAP.md` — the full learning → decide → apply loop
- `docs/LEARNING-APPLY.md` — operator reference (lanes, flags, bounds)
- `references/lanes.md` — config-key map + per-field bounds
- `skills/consensus-arbiter/SKILL.md` — the diff-first pattern reused here
- `skills/apply-arbiter-patch/SKILL.md` — the preview/`--yes` apply pattern
