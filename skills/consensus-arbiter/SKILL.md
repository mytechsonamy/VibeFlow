---
name: consensus-arbiter
description: Reads the verdict + reviewer suggestions from a consensus session, evaluates each suggestion against the current SDLC phase + domain, and emits diff-first patches for the ones that should APPLY. Never writes to source files — only to `.vibeflow/state/patches/<session>/` and `.vibeflow/reports/arbiter-decisions.md`. Invoke via `/vibeflow:apply-arbiter-patch` to actually apply.
disable-model-invocation: true
allowed-tools: Read Write Grep Glob Bash(jq *) Bash(mkdir *) Bash(rm *)
context: fork
agent: Explore
---

# Consensus Arbiter

Closes the MyVibe loop. The orchestrator gave us three verdicts +
suggestions; this skill decides **which suggestions belong in the
current phase** and produces `.patch` files the operator can apply
safely. We never Write to source files here — that's the separate
`apply-arbiter-patch` skill's job.

## Phase Contract

This skill runs in **any phase** (the decision matrix handles
phase-relevance filtering per-suggestion). Before any other step,
read `vibeflow.config.json.currentPhase` for context; if it's
missing emit `"arbiter needs vibeflow.config.json — run /vibeflow:init
first"` and stop.

## Input

- `$ARGUMENTS` — session id (required, e.g. `1101628e-…`).
  The orchestrator auto-invokes this skill after `NEEDS_REVISION`
  verdicts and passes the session id as the argument. When invoked
  manually, point at the latest session under
  `.vibeflow/state/consensus/`.

Files read (relative to `$(vf_cwd)`):

- `.vibeflow/state/consensus/<session>.jsonl` — per-reviewer rows
  with `suggestions[]` (Sprint 15-E schema)
- `.vibeflow/state/consensus/<session>.verdict.json` — aggregated
  verdict (aggregator's output)
- `vibeflow.config.json` — `currentPhase`, `domain`, `riskTolerance`,
  any `consensus.arbiter` overrides
- The original artifact(s) named in suggestion `target.file` — only
  to sanity-check the line range; no writes.

## Process

### Step 1: Load the session

```
SESSION=$1
CONS_DIR=$(vf_state_dir)/consensus
JSONL="$CONS_DIR/$SESSION.jsonl"
VERDICT="$CONS_DIR/$SESSION.verdict.json"

[ -f "$JSONL" ]   || fail "missing jsonl for session $SESSION"
[ -f "$VERDICT" ] || fail "missing verdict.json for session $SESSION"
```

Merge all reviewers' `suggestions[]` into a single list. Tag each
with `source=<reviewer>` so the decision matrix can spot overlaps
across Claude + codex + gemini.

### Step 2: Load context

```
PHASE=$(jq -r '.currentPhase' vibeflow.config.json)
DOMAIN=$(jq -r '.domain' vibeflow.config.json)
TOLERANCE=$(jq -r '.riskTolerance // "medium"' vibeflow.config.json)
```

### Step 3: Decision matrix

For each suggestion, apply the rules in order — first match wins:

| Condition | Decision |
|---|---|
| `phase_relevance` present and `PHASE` not in it | **DEFER** (forward to target phase log) |
| `type == "question"` | **DEFER** (answer belongs in the artifact reply, not a patch) |
| Domain policy conflict (e.g. `financial` domain + suggestion weakens an invariant weight, loosens a threshold, or drops an audit requirement) | **REJECT** + rationale |
| `proposed_change` is empty / vague / < 30 chars | **DEFER** ("needs more detail") |
| Two or more reviewers propose similar changes targeting same file + overlapping line range + `priority >= medium` | **APPLY** (consolidated — cite all sources) |
| Single reviewer, `priority == "low"` | **DEFER** (arbiter threshold) |
| Single reviewer, `priority >= "medium"` AND `type == "fix"` | **APPLY** |
| Single reviewer, `priority >= "medium"` AND `type == "enhancement"` | **DEFER** when `TOLERANCE == "low"`, else **APPLY** |
| Two reviewers disagree on same target (conflict) | **DEFER** + "manual resolution needed" |
| Otherwise | **DEFER** |

Record every decision (APPLY / DEFER / REJECT) with its rationale —
the operator will want an audit trail.

### Step 4: Synthesise patches

For each APPLY, read the target file and produce a unified diff. The
reviewer's `proposed_change` may be a natural-language description
or a concrete text fragment. In either case:

- Load the file at `target.file`.
- Determine the replacement region from `target.line_range`; if absent,
  pick the smallest enclosing block (paragraph for `.md`, function for
  code) that makes the change unambiguous.
- Produce a `git apply`-compatible patch (`--- a/…`, `+++ b/…`, `@@ …`
  hunks). One patch file per APPLY decision.
- Name: `<n>-<slug>.patch` where `n` is the APPLY ordinal (01, 02, …)
  and `slug` is a short kebab-case summary of the change.

Patches land under `.vibeflow/state/patches/<session>/`. Never write
to the source file itself — the patch files are the only outputs.

### Step 5: Write the decision log

`.vibeflow/reports/arbiter-decisions.md` — human-readable audit
trail:

```markdown
# Arbiter Decisions — session <session>

## Context
- Phase: <PHASE>
- Domain: <DOMAIN>
- Risk tolerance: <TOLERANCE>
- Verdict: <verdict.json.status>
- Reviewers: claude (<N suggestions>), codex (<N>), gemini (<N>)
- Iteration: 1  (see §Iteration guard)

## Summary
- APPLY: <count>
- DEFER: <count>
- REJECT: <count>

## Decisions

### APPLY (N)
1. **<suggestion summary>** — priority=<p>, target=<file>:<lines>
   Sources: claude-3, codex-2
   Rationale: <one sentence>
   Patch: .vibeflow/state/patches/<session>/01-<slug>.patch
   Applied: false   # flips to true via /vibeflow:apply-arbiter-patch

### DEFER (N)
1. <summary> — deferred because <rule>. Target phase: <PHASE>.

### REJECT (N)
1. <summary> — rejected because <domain policy / rule>.
```

### Step 6: Manifest + iteration guard

`.vibeflow/state/patches/<session>/manifest.json`:

```json
{
  "sessionId": "<session>",
  "generatedAt": "<ISO>",
  "phase": "<PHASE>",
  "iteration": 1,
  "apply": [
    { "file": "01-<slug>.patch", "target": "<file>", "sources": ["claude-3","codex-2"] }
  ]
}
```

`iteration` prevents the "orchestrator → arbiter → apply → orchestrator
→ NEEDS_REVISION → arbiter" infinite loop. If the manifest sees a
previous iteration for the same artifact that already hit iteration
3, fall through to `deferred_for_human_review` and stop producing
patches.

### Step 7: Close

Emit to the model (not to a file):

```
Arbiter session <session> complete.
  APPLY: <N> patches under .vibeflow/state/patches/<session>/
  DEFER: <N> (see arbiter-decisions.md)
  REJECT: <N>

To preview + apply the patches, run:
  /vibeflow:apply-arbiter-patch <session>
```

## Output Files

Every run writes to `.vibeflow/`:

- `.vibeflow/reports/arbiter-decisions.md`
- `.vibeflow/state/patches/<session>/manifest.json`
- `.vibeflow/state/patches/<session>/NN-<slug>.patch` (one per APPLY)

## Final Step: Drain the consensus-needed marker (Sprint 16-B)

After writing all output files, defensively drain the Sprint 16-A
marker even though the orchestrator already dropped it:

```bash
rm -f "$(vf_state_dir)/consensus-needed.json"
rm -f "$(vf_state_dir)/review-pending.json"
```

**Why:** when the operator invokes `/vibeflow:consensus-arbiter`
directly (not via the orchestrator auto-chain) the marker may still
be in place from a prior skill run. Leaving it set would block the
very next `/vibeflow:apply-arbiter-patch` call — the arbiter's
entire point. Drain unconditionally at the end of a successful run.

## Downstream Dependencies

- `apply-arbiter-patch` reads the manifest + patches and offers them
  to the operator with a diff preview.
- `learning-loop-engine` (Sprint 18+ candidate) may consume the
  decision log across runs to tune the decision matrix thresholds.

## Final Step: No Auto-Consensus

Unlike the L1 analysis skills (Sprint 15-B), this skill **does not**
chain back into consensus-orchestrator. The orchestrator already ran
upstream; re-invoking it on `arbiter-decisions.md` would be
circular. Apply happens manually via `/vibeflow:apply-arbiter-patch`.
