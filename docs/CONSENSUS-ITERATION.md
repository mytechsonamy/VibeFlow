# Consensus Iteration (Sprint 17)

VibeFlow v2.5.0 ships the iterative consensus loop promised by
MyVibe's original design. Reviewers (Claude + codex + gemini) talk
to each other across multiple rounds, each reading the previous
round's verdicts + top findings, until one of: (1) early
convergence, (2) a hard reject, or (3) `maxIterations` rounds
elapse without crossing the approval threshold.

## Loop shape

```
round=1
while round <= consensus.maxIterations:
    for each reviewer (codex, gemini, claude-reviewer):
        if round == 1:
            prompt = base review prompt
        else:
            prompt = base + prior-round verdicts + top findings
        run reviewer, append verdict line to session jsonl

    aggregate current round → verdict.json.rounds[round-1]

    if status == APPROVED:
        stopReason = "earlyConverged"; break
    if status == REJECTED:
        stopReason = "hardReject"; break
    if consensus.iteration.enabled == false:
        stopReason = "iterationDisabled"; break

    round += 1

if round > consensus.maxIterations:
    stopReason = "maxRounds"
    if agreement >= 0.5 and not rejected-majority:
        status = HUMAN_APPROVAL_REQUIRED   # pass-with-audit
    # else leave as NEEDS_REVISION / REJECTED per normal rules

write verdict.json.iterationStopReason = stopReason
remove current-round.txt marker
```

## Config surface

All values read from `vibeflow.config.json` or falls back to
defaults:

| Key                                 | Default | Range         |
|-------------------------------------|---------|---------------|
| `consensus.maxIterations`           | 5       | [1, 20]       |
| `consensus.approvalThreshold`       | 0.9     | [0, 1]        |
| `consensus.iteration.enabled`       | true    | boolean       |
| `consensus.quorum`                  | auto    | integer ≥ 1   |

`consensus.iteration.enabled: false` is the rollback switch — the
loop falls through to a single round (pre-2.5.0 behaviour). The
orchestrator still writes `rounds[{round:1, ...}]` so downstream
consumers don't branch.

## Status values

Enum: APPROVED / NEEDS_REVISION / REJECTED / **HUMAN_APPROVAL_REQUIRED**
(Sprint 17-C).

- **APPROVED** — `agreement >= approvalThreshold AND criticalDedup == 0`
- **REJECTED** — `criticalDedup >= 2` OR `rejected * 2 > total`
  (majority rejected)
- **HUMAN_APPROVAL_REQUIRED** — `maxIterations` exhausted,
  agreement in [0.5, approvalThreshold), no rejected-majority,
  no ≥2 dedup'd critical findings. Pass-with-audit.
- **NEEDS_REVISION** — anything else. Orchestrator offers both
  arbiter (mechanical patches) and specialist (deep rewrite).

## `rounds[]` schema in verdict.json

```json
{
  "sessionId": "…",
  "status": "APPROVED",
  "finalRound": 3,
  "iterationStopReason": "earlyConverged",
  "rounds": [
    {"round":1, "agreement":0.58, "criticalTotal":5, "status":"NEEDS_REVISION"},
    {"round":2, "agreement":0.74, "criticalTotal":3, "status":"NEEDS_REVISION"},
    {"round":3, "agreement":0.92, "criticalTotal":0, "status":"APPROVED"}
  ],
  "agreement": 0.92,
  "criticalTotal": 0,
  "criticalRawCount": 0,
  "criticalDeduped": [],
  "timeout": false,
  "expectedReviewers": 3,
  "receivedReviewers": 3,
  "finalizedAt": "2026-04-21T12:30:00Z"
}
```

Top-level `status`/`agreement`/`criticalTotal` always reflect the
final (latest) round — pre-2.5.0 consumers keep working without
branching.

## Critical dedup (Sprint 17-B)

`criticalIssues` in reviewer output is now an array of entries:

```json
[
  {
    "id": "claude-c1",
    "target": { "file": "docs/prd.md", "line_range": [120, 145] },
    "title": "Data residency for BDDK BİSY missing",
    "rationale": "7-year audit logs + muhabir API transit must be…"
  }
]
```

Three reviewers flagging the same `{file, line_range}` (or with
Jaccard-similar titles ≥ 0.6) deduplicate to **one** `criticalTotal`.
Before 2.5.0 the aggregator summed these and promoted NEEDS_REVISION
to REJECTED at 2; unanimous NEEDS_REVISION with overlapping findings
no longer falsely escalates.

Legacy integer form (`"criticalIssues": 3`) still parses — the
aggregator falls back to summing and logs the `criticalRawCount`
field for audit.

## HUMAN_APPROVAL_REQUIRED flow (pass-with-audit)

When the loop ends at round N without convergence:

```
Orchestrator writes verdict.json.status = "HUMAN_APPROVAL_REQUIRED"
  │
  ▼
Operator runs /vibeflow:advance <next-phase> humanOverrideNote="…"
  │
  ▼
sdlc_advance_phase MCP tool:
  - validation.ts accepts HUMAN_APPROVAL_REQUIRED alongside APPROVED
  - engine.ts threads humanOverrideNote into the phase_advanced event
  - filesystem StateStore writes .vibeflow/state/<project>/events/NNNN-phase_advanced.json
    with payload.humanOverrideNote populated
  │
  ▼
load-sdlc-context.sh (next SessionStart):
  finds the latest phase_advanced event with humanOverrideNote
  emits visible advisory line:
  "VibeFlow: last phase advance (REQUIREMENTS → DESIGN at 2026-04-21)
   ran under HUMAN_APPROVAL_REQUIRED.
     Override note: YÖS tier resolved offline with Legal."
```

The audit line stays visible on every subsequent SessionStart until
a new `phase_advanced` event without `humanOverrideNote` supersedes
it — keeping the override present in the operator's peripheral
vision.

## Auto-chain on apply (Sprint 19-E)

Before v2.7.0, the operator had to invoke
`/vibeflow:consensus-orchestrator` again after
`/vibeflow:apply-arbiter-patch` to verify that the patches
actually converged the primary artifact. Sprint 19-E closes that
gap: on successful apply (plus passing tests when `--run-tests`),
the skill writes a fresh `consensus-needed.json` marker pointing
back at the same primaryArtifact, and `consensus-gate` blocks
the next tool call with the required command.

```
apply-arbiter-patch (round N succeeds)
  │
  ▼  Step 9: auto-chain writes marker v2
consensus-needed.json:
  primaryArtifact = <carried from original session>
  evidence        = original evidence + arbiter-decisions.md
  autoChain       = { round: N+1, parentSessionId: <sid> }
  │
  ▼
consensus-gate blocks next Bash/Write/Edit with:
  "RUN THIS NEXT: /vibeflow:consensus-orchestrator <primary>"
  │
  ▼
round N+1 reviewer panel evaluates the UPDATED artifact
```

**Guardrails:**
- `--no-chain` CLI flag or `VF_SKIP_AUTO_CHAIN=1` env override.
- Max-iterations stop: if `N+1 > consensus.maxIterations`, write
  `.vibeflow/reports/max-iterations-reached.md` advisory instead.
- Convergence-stall guard: if
  `|verdict(N).agreement - verdict(N-1).agreement| ≤ 0.05` and
  `N ≥ 2`, write `.vibeflow/reports/convergence-stalled.md` and
  stop. Prevents infinite spin when specialist rewrites aren't
  actually moving the needle.

**Iteration storage.** Tracked in the existing `verdict.json.round`
field (Sprint 17-A) — no new `manifest.iteration` state file. Apply
reads the latest `round`, increments, and writes the next-round
marker carrying the same primary artifact.

## Escape hatches

- **`consensus.iteration.enabled: false`** — single-round behaviour
  (2.4.0 parity). Useful to A/B compare a change against the
  pre-17 flow.
- **`VF_SKIP_AUTO_CONSENSUS=1`** — disables Layer 2 marker-writing
  on analysis skills (Sprint 16). Iteration loop is untouched;
  orchestrator still runs when invoked manually.
- **`VF_SKIP_CONSENSUS_GATE=1`** — per-call bypass of the
  PreToolUse consensus-gate hook.
- **`humanOverrideNote`** — per-advance override for
  HUMAN_APPROVAL_REQUIRED (Sprint 17-C, pass-with-audit). Goes
  to the audit trail; surfaces on load-sdlc-context.

## Troubleshooting

### "Round N never finished"

Each CLI has a 90s per-round timeout. If a CLI hangs past 90s, it
contributes a `REJECTED + note: cli_timeout` line to the jsonl and
the aggregator proceeds. A full round with 3 timeouts looks like
3 REJECTED → majority reject → round stops as REJECTED. Not
iteration's fault — swap to `consensus.quorum: 1` or set a CLI
model you know responds.

### "Rounds[] is empty on verdict.json"

Check `.vibeflow/state/consensus/<sid>.current-round.txt` — if the
file doesn't exist, the orchestrator didn't run its iteration
loop (maybe `consensus.iteration.enabled: false`, or the
orchestrator was invoked from a fork without access to the
marker). `rounds[]` should still have at least `[{round:1, …}]`
from the first aggregation.

### "HUMAN_APPROVAL_REQUIRED but I really want APPROVED"

Run another round manually. Write a new
`.vibeflow/state/consensus/<sid>.current-round.txt` with
`maxIterations+1`, re-invoke the reviewer panel with more context,
and the aggregator will append a new entry to `rounds[]`. Or
invoke `/vibeflow:consensus-specialist <sid>` to have the phase
specialist rewrite the artifact deeply — review their patch, apply
it, then run a fresh consensus session.

### "Specialist patch conflicts with arbiter patch"

Both go into `.vibeflow/state/patches/<sid>/`. Their `manifest.json`
entries carry `type: "arbiter"` or `type: "specialist"` and
`apply-arbiter-patch` processes them in order. If they target
overlapping line ranges, the second one fails `git apply --check`
and the apply skill aborts with a "run specialist first, then
arbiter on a fresh session" hint.

## The agreement curve feeds the slow loop (Sprint 20)

Every round's `verdict.json` carries a `rounds[]` array with the
per-round `agreement` value — the convergence curve. Sprint 20
persists each round as a row in
`.vibeflow/state/consensus/history.jsonl`, and pairs it with the
`arbiter-decision` row that `apply-arbiter-patch` writes. The
**effectiveness trace** in `learning-loop-engine --mode
consensus-history` joins applied themes at round R against the
agreement delta at round R+1: a theme that is applied but never moves
agreement is flagged `ineffective-theme`, so the loop stops grinding
on cosmetic fixes while the substantive objection stands. See
[LEARNING-LOOP.md](LEARNING-LOOP.md).
