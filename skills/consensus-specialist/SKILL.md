---
name: consensus-specialist
description: Dispatches a phase-specific specialist subagent (prd-rewriter, adr-author, test-strategy-refiner, coverage-gap-filler, design-spec-refiner, or runbook-editor) to deeply rewrite an artifact based on multi-AI reviewer feedback. Diff-first contract — never writes to source directly. Use when the arbiter's mechanical patches aren't enough and the phase needs structural rework.
disable-model-invocation: true
allowed-tools: Read Write Bash(jq *) Bash(mkdir *) Bash(rm *) Grep Glob
---

# Consensus Specialist (Sprint 17-E)

Dispatcher skill that picks the right phase-specialist agent and
forks it. Invoked by the operator with:

```
/vibeflow:consensus-specialist [<session-id>]
```

Default session id: the most recent `.verdict.json` under
`.vibeflow/state/consensus/`.

## When to use this vs. the arbiter

The orchestrator emits two paths on NEEDS_REVISION /
HUMAN_APPROVAL_REQUIRED:

- `/vibeflow:consensus-arbiter <sid>` — mechanical, one small
  patch per reviewer `suggestion`. Conservative, fast, no
  interpretation. Default.
- `/vibeflow:consensus-specialist <sid>` — deep rewrite by a
  phase expert. One larger patch that resolves structural gaps
  the reviewers only hinted at. Use when `suggestions[]` read
  like "this whole section needs rework" rather than "fix line
  42".

Both produce diff-first patches that feed into
`/vibeflow:apply-arbiter-patch` for preview + confirm + apply.

## Phase → Specialist Map (Sprint 17-D)

The skill reads `vibeflow.config.json.currentPhase` and dispatches:

| currentPhase | Specialist agent | Primary outputs |
|---|---|---|
| REQUIREMENTS | `prd-rewriter` | PRD rewrite patch + decisions doc |
| DESIGN | `design-spec-refiner` | design spec rewrite patch |
| ARCHITECTURE | `adr-author` | new ADR files + architecture.md updates |
| PLANNING | `test-strategy-refiner` | scenario-set + test-strategy.md expansion |
| TESTING | `coverage-gap-filler` | new test files / expansions |
| DEPLOYMENT | `runbook-editor` | runbook + release-notes + rollback updates |

## Process

### Step 1: Resolve session

```bash
STATE_DIR="$(vf_state_dir)"
CONS_DIR="$STATE_DIR/consensus"
SESSION_ID="${ARGUMENTS:-}"
if [[ -z "$SESSION_ID" ]]; then
  # Pick the most-recent verdict.json if no argument supplied.
  SESSION_ID="$(ls -t "$CONS_DIR"/*.verdict.json 2>/dev/null | head -1 | xargs -I{} basename {} .verdict.json)"
fi
[ -z "$SESSION_ID" ] && { echo "No consensus session found"; exit 1; }
```

Read `$CONS_DIR/$SESSION_ID.verdict.json` and apply the **4-case
guardrail** (Sprint 19-D). The Sprint 19-C aggregator refactor
eliminated "soft REJECTED" (0 reject votes + ≥2 critical now lands
as NEEDS_REVISION, not REJECTED), so REJECTED always means at
least one reviewer actually voted reject.

```bash
STATUS="$(jq -r '.status' "$VERDICT")"
REJECTED_COUNT="$(jq -r '.rejected // 0' "$VERDICT")"

case "$STATUS" in
  APPROVED)
    echo "Nothing to rewrite — the artifact passed consensus."
    exit 0
    ;;
  REJECTED)
    if (( REJECTED_COUNT >= 1 )); then
      echo "Genuine reject: $REJECTED_COUNT reviewer(s) voted REJECTED."
      echo "Findings require operator triage before specialist rewrite is reasonable."
      exit 0
    fi
    # Fall through — zero-reject REJECTED shouldn't happen post-S19-C,
    # but the path stays defensive for pre-2.7.0 verdict files.
    echo "Soft REJECTED detected (legacy verdict, 0 reject votes). Treating as NEEDS_REVISION."
    ;;
  NEEDS_REVISION|HUMAN_APPROVAL_REQUIRED)
    : # dispatch specialist — the common case
    ;;
  *)
    echo "Unknown verdict status: $STATUS"
    exit 1
    ;;
esac
```

**The 4-case decision matrix:**

| Status | rejected≥1 | Action |
|---|---|---|
| APPROVED | — | stop: "nothing to rewrite" |
| REJECTED | ≥1 | stop: "genuine reject — operator triage" |
| REJECTED | 0 (legacy) | proceed as NEEDS_REVISION |
| NEEDS_REVISION | any | dispatch specialist |
| HUMAN_APPROVAL_REQUIRED | any | dispatch specialist (per Sprint 17-C) |

### Step 2: Resolve phase

```bash
CURRENT_PHASE="$(vf_config_get '.currentPhase' 2>/dev/null || echo '')"
```

Map the phase to the specialist agent name per the table above. If
the phase is unknown or missing, stop and prompt the operator to
run `/vibeflow:onboard` first.

### Step 3: Prepare patch directory

```bash
PATCH_DIR="$STATE_DIR/patches/$SESSION_ID"
mkdir -p "$PATCH_DIR"
```

If a `manifest.json` is present (from a prior arbiter run), read
its patches count so the specialist's patch gets the next
zero-padded index. Otherwise start at `specialist-01-<phase>.patch`.

### Step 4: Dispatch the specialist

Based on `CURRENT_PHASE`, invoke the matching subagent by name.
In Claude Code this is a natural-language instruction the model
resolves via its standard subagent-dispatch tool. Pass the
session id + the target artifact path as arguments:

- REQUIREMENTS → invoke the `prd-rewriter` subagent
- DESIGN → invoke the `design-spec-refiner` subagent
- ARCHITECTURE → invoke the `adr-author` subagent
- PLANNING → invoke the `test-strategy-refiner` subagent
- TESTING → invoke the `coverage-gap-filler` subagent
- DEPLOYMENT → invoke the `runbook-editor` subagent

The specialist reads:
- `$CONS_DIR/$SESSION_ID.verdict.json`
- the round-archive jsonls under `$CONS_DIR/`
- the primary artifact referenced in reviewer suggestions

and writes:
- `$PATCH_DIR/specialist-NN-<phase>.patch`
- `.vibeflow/reports/specialist-decisions-<phase>.md`

The specialist runs `context: fork` so it can't invoke slash
commands on its own — that's why we produce a patch + decision
report and hand off to the operator here.

### Step 5: Update manifest + print follow-up

After the specialist returns, update (or create)
`$PATCH_DIR/manifest.json`:

```json
{
  "sessionId": "<sid>",
  "patches": [
    { "index": "NN", "type": "specialist", "file": "specialist-NN-<phase>.patch", "agent": "<specialist-name>", "createdAt": "<ISO>" }
  ]
}
```

If a prior `manifest.json` exists, append to its `patches[]`; the
apply skill processes entries in order.

### Step 6: Drain the consensus-needed marker (Sprint 16-B)

Successful specialist run ends the review loop from the operator's
point of view, so drain both markers:

```bash
rm -f "$STATE_DIR/review-pending.json"
rm -f "$STATE_DIR/consensus-needed.json"
```

The `consensus-gate` hook (Sprint 16-A) won't block the subsequent
`/vibeflow:apply-arbiter-patch` call — but keeping the markers
clean protects against the operator invoking the specialist
directly (skipping orchestrator) on a stale session.

### Step 7: Operator handoff

Print a visible summary + next-step command. Example shape:

```
Specialist <name> produced 1 patch:

  .vibeflow/state/patches/<sid>/specialist-NN-<phase>.patch
     affects: docs/prd.md (+58, -12)
     addresses: 7 findings, deferred 3
     rationale: see .vibeflow/reports/specialist-decisions-<phase>.md

Next:
  /vibeflow:apply-arbiter-patch <sid>
      (shows diff preview → y/n → git apply; add --run-tests to
       verify tests pass post-apply)

Rollback (if applied patch breaks something):
  git checkout HEAD -- <affected files>
```

## Guardrails

- **Only one specialist per session.** If `manifest.json` already
  has a specialist entry for this session, refuse to run again
  unless `--force` is passed (otherwise two specialists on the
  same verdict = conflicting patches).
- **Read-only until output.** The specialist is `context: fork`
  and disallowed from Edit/Write outside the patch + report
  paths. Arbiter/apply invariants stay intact.
- **No slash-command chaining.** This skill does not invoke
  `/vibeflow:apply-arbiter-patch` itself — that's the operator's
  explicit choice after reviewing the decision report.

## Non-goals

- **No phase inference.** If `currentPhase` is wrong, fix the
  phase via `/vibeflow:flow-status` + `/vibeflow:advance` first.
- **No multi-patch output.** One specialist invocation = one
  patch. If the session needs both mechanical and deep rewrites,
  run arbiter first, apply, then run specialist on a fresh
  consensus session.
- **No implementation in DESIGN / REQUIREMENTS.** Specialists
  stay inside their phase's artifact envelope — they never
  leak into `src/**` outside TESTING (where coverage-gap-filler
  may add test code).
