---
name: consensus-orchestrator
description: Orchestrates multi-AI review process. Coordinates Claude, ChatGPT (codex CLI), and Gemini (gemini CLI) reviews. Each CLI's verdict is appended to the session jsonl the aggregator reads, per-CLI 90s timeout so the aggregator never falls through to its 600s global wait. On NEEDS_REVISION verdicts the skill auto-invokes consensus-arbiter to decide which reviewer suggestions are applicable to the current phase.
disable-model-invocation: true
allowed-tools: Read Write Bash(codex *) Bash(gemini *) Bash(jq *) Bash(timeout *) Bash(rm *) Bash(mkdir *) Grep Glob
---

# Consensus Orchestrator

Manages the multi-AI review cycle that replaces MyVibe's CLI subprocess approach. Fixes Bug #1 (case mismatch), Bug #2 (model names), and Bug #8 (no CLI fallback).

## Input
- $ARGUMENTS: Path to artifact(s) to review, or "review last commit"
- vibeflow.config.json: model names, domain

## Consensus Flow

### Step 1: Read Configuration
```
openaiModel = vibeflow.config.json.models.openai  // default: "gpt-4o" (NOT gpt-5.3!)
geminiModel = vibeflow.config.json.models.gemini   // default: "gemini-2.0-flash"
```

**Note (Sprint 14-A):** There is no `mode` concept anymore. Every
reviewer participation is decided by CLI availability — codex and
gemini join the panel when their CLIs are on `PATH`, full stop. Both
CLIs use the operator's own authenticated session, so there is no
API billing concern to gate on.

### Step 2: Claude Review (Always Available)
Use the claude-reviewer subagent for native review. This always runs.

### Step 3: External AI Reviews (CLI-availability only)
Run every CLI that is on `PATH`. Skip the ones that aren't — never
gate on a mode switch, environment variable, or config flag.

**ChatGPT Review (via codex CLI):**
```bash
if command -v codex &>/dev/null; then
  cat <artifact> | codex exec "Review this for quality, security, maintainability. Return JSON: {score, issues, verdict}" -m $openaiModel --skip-git-repo-check --ephemeral
fi
```

**Gemini Review (via gemini CLI):**
```bash
if command -v gemini &>/dev/null; then
  (echo "Review this for quality, security, maintainability. Return JSON: {score, issues, verdict}" && cat <artifact>) | gemini --model $geminiModel
fi
```

Both CLIs inherit the operator's authenticated session (ChatGPT
subscription, Gemini Pro, Workspace, etc.). There is no VibeFlow-
emitted API key and no per-call billing.

### Step 3b: CLI Output Capture (Sprint 15-A)

The `codex` and `gemini` calls above are **raw bash processes** — they
do NOT emit Claude Code `SubagentStop` events, so
`consensus-aggregator.sh` never sees them on its own. To close the
loop you MUST, for each CLI you ran, append one JSONL record to the
aggregator's session log in the exact shape the aggregator expects
(see `hooks/scripts/consensus-aggregator.sh:110-116`):

```bash
# $SESSION_ID comes from the SubagentStop that will fire when
# claude-reviewer finishes (Step 2). Use the same session id so all
# three reviewers merge into one verdict. In prose: "use the current
# Claude Code session id; if unavailable, generate a uuid once at
# the start of this skill invocation and reuse it everywhere below."
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen)}"
STATE_DIR="$(vf_state_dir)"  # .vibeflow/state/
CONS_DIR="$STATE_DIR/consensus"
mkdir -p "$CONS_DIR"
LOG="$CONS_DIR/$SESSION_ID.jsonl"

append_cli_verdict() {
  local reviewer="$1" raw="$2" note="${3:-}"
  local verdict critical structured
  # Prefer structured JSON output: {"verdict":"...","criticalIssues":N, "suggestions":[...]}
  structured="$(printf '%s' "$raw" | jq -Rsr 'try (fromjson | .verdict) catch empty' 2>/dev/null || true)"
  case "$structured" in
    APPROVED|NEEDS_REVISION|REJECTED) verdict="$structured" ;;
    *)
      # Free-text fallback — keyword precedence (REJECTED > NEEDS_REVISION > APPROVED).
      if echo "$raw" | grep -qE 'REJECTED'; then verdict=REJECTED
      elif echo "$raw" | grep -qE 'NEEDS_REVISION|NEEDS[[:space:]]REVISION'; then verdict=NEEDS_REVISION
      elif echo "$raw" | grep -qE 'APPROVED'; then verdict=APPROVED
      else verdict=NEEDS_REVISION  # unparseable → safe default
      fi
      ;;
  esac
  critical="$(printf '%s' "$raw" | jq -Rsr 'try (fromjson | .criticalIssues | if type=="array" then length else . end) catch 0' 2>/dev/null || echo 0)"
  [[ "$critical" =~ ^[0-9]+$ ]] || critical=0

  # Sprint 17-B: preserve the structured `criticalIssues[]` array (if
  # the reviewer emitted one) so the aggregator can dedup across
  # reviewers by {file, line_range} + Jaccard(title). Legacy integer
  # shape gets an empty array.
  critical_items="$(printf '%s' "$raw" | jq -Rsr 'try (fromjson | .criticalIssues | if type=="array" then tojson else "[]" end) catch "[]"' 2>/dev/null || echo "[]")"

  # Sprint 17-A: read current round from marker; default 1.
  local round=1
  if [[ -f "$CONS_DIR/$SESSION_ID.current-round.txt" ]]; then
    local mv_round
    mv_round="$(head -n1 "$CONS_DIR/$SESSION_ID.current-round.txt" 2>/dev/null | tr -d '[:space:]')"
    [[ "$mv_round" =~ ^[0-9]+$ ]] && (( mv_round >= 1 )) && round="$mv_round"
  fi

  jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg reviewer "$reviewer" \
    --arg verdict "$verdict" \
    --argjson critical "$critical" \
    --argjson criticalItems "$critical_items" \
    --arg note "$note" \
    --argjson round "$round" \
    --argjson raw "$(printf '%s' "$raw" | jq -Rsr 'try fromjson catch {}' 2>/dev/null || echo '{}')" \
    '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical, criticalItems:$criticalItems, round:$round, note:$note, suggestions:($raw.suggestions // [])}' \
    >> "$LOG"
}

# codex — 90s per-CLI timeout so aggregator never sits on its 600s global wait.
if command -v codex >/dev/null 2>&1; then
  CODEX_OUT="$(timeout 90 codex exec "Review this for quality/security/maintainability. Output ONLY valid JSON matching {verdict:APPROVED|NEEDS_REVISION|REJECTED, score:0-100, criticalIssues:N, summary:string, suggestions:[{id,type,target:{file,line_range:[s,e]},rationale,proposed_change,priority,phase_relevance:[]}]}" -m "$openaiModel" --skip-git-repo-check --ephemeral < "$ARTIFACT" 2>&1)"
  CODEX_RC=$?
  if (( CODEX_RC == 124 )); then
    append_cli_verdict codex '{"verdict":"REJECTED","criticalIssues":0}' "cli_timeout"
  elif (( CODEX_RC != 0 )); then
    append_cli_verdict codex '{"verdict":"REJECTED","criticalIssues":0}' "cli_error:$CODEX_RC"
  else
    append_cli_verdict codex "$CODEX_OUT" ""
  fi
fi

# gemini — same shape.
if command -v gemini >/dev/null 2>&1; then
  GEMINI_OUT="$(timeout 90 sh -c "(echo 'Review this for quality/security/maintainability. Output ONLY valid JSON {verdict, score, criticalIssues, summary, suggestions[]}' && cat '$ARTIFACT') | gemini --model '$geminiModel'" 2>&1)"
  GEMINI_RC=$?
  if (( GEMINI_RC == 124 )); then
    append_cli_verdict gemini '{"verdict":"REJECTED","criticalIssues":0}' "cli_timeout"
  elif (( GEMINI_RC != 0 )); then
    append_cli_verdict gemini '{"verdict":"REJECTED","criticalIssues":0}' "cli_error:$GEMINI_RC"
  else
    append_cli_verdict gemini "$GEMINI_OUT" ""
  fi
fi
```

After the CLIs are logged, spawn the claude-reviewer subagent (Step 2)
**last** — its SubagentStop fires `consensus-aggregator.sh`, which
sees all three jsonl entries and finalises the session as one.

### Step 3c: Post-consensus state registration + cleanup (Sprint 15-A, 16-B, 17.2)

Once the aggregator has written `.vibeflow/state/consensus/<session>.verdict.json`:

#### 3c.0 — Record consensus into project state (Sprint 17.2, MANDATORY)

Read verdict.json and call the `sdlc_record_consensus` MCP tool
immediately. Without this, the phase-gate validator has no
`lastConsensus` to check and `/vibeflow:advance` blocks even on
APPROVED verdicts. Required for **every** terminal status
(APPROVED / NEEDS_REVISION / REJECTED / HUMAN_APPROVAL_REQUIRED).

Read the config + verdict:
```bash
PROJECT_ID="$(vf_config_get '.project')"
PHASE="$(vf_config_get '.currentPhase')"
STATUS="$(jq -r '.status' "$CONS_DIR/$SESSION_ID.verdict.json")"
AGREEMENT="$(jq -r '.agreement // 0' "$CONS_DIR/$SESSION_ID.verdict.json")"
CRITICAL="$(jq -r '.criticalTotal // 0' "$CONS_DIR/$SESSION_ID.verdict.json")"
```

Then invoke the MCP tool (Claude resolves this as a standard
`mcp__sdlc-engine__sdlc_record_consensus` tool call — no extra
bash plumbing needed):

```
mcp__sdlc-engine__sdlc_record_consensus {
  "projectId": "<project id from config>",
  "phase":     "<currentPhase from config>",
  "status":    "<verdict.json .status>",
  "agreement": <verdict.json .agreement>,
  "criticalIssues": <verdict.json .criticalTotal>
}
```

This single call writes `lastConsensus: {phase, status, agreement,
criticalIssues, recordedAt}` into project.json. The validator's
scope check for `consensus.<phase>.approved` reads it on the
next `/vibeflow:advance`.

Failure modes:
- MCP tool not available (e.g. Claude Code launched without
  sdlc-engine loaded): emit a visible "could not record consensus
  to project state; run `mcp__sdlc-engine__sdlc_record_consensus`
  manually with …" prose. Do NOT fail the orchestrator — the
  verdict.json is the source of truth on disk.
- Project state missing (`sdlc_get_state` returns null): the
  MCP server auto-seeds on first write, so this is not a blocker.

#### 3c.0b — DEVELOPMENT-phase auto-satisfy code.reviewed (Sprint 18-E)

DEVELOPMENT is the one phase without a scoped
`consensus.<phase>.approved` exit criterion (Sprint 15-C
excluded it because commit-time review is the authoritative
review signal). That means DEVELOPMENT's `code.reviewed` exit
criterion needs its own satisfier — and the orchestrator's
DEVELOPMENT verdict is exactly that signal: "reviewers have
seen this code and either approved it outright or accepted it
under explicit human override."

When **all three** of these hold:

1. `PHASE == DEVELOPMENT` (from `vibeflow.config.json.currentPhase`)
2. `STATUS == APPROVED` OR `STATUS == HUMAN_APPROVAL_REQUIRED`
3. The record-consensus call above succeeded (or was skipped
   only because MCP was unreachable — in the MCP-unreachable
   case, skip this step too; the operator's fallback path
   covers both criteria)

also call:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id>",
  "criterion": "code.reviewed"
}
```

Emit a one-line confirmation:

```
Recorded: code.reviewed (phase=DEVELOPMENT, verdict=<APPROVED|HUMAN_APPROVAL_REQUIRED>).
```

On REJECTED / NEEDS_REVISION in DEVELOPMENT: do NOT satisfy
`code.reviewed`. The gate correctly blocks DEVELOPMENT →
TESTING until a fresh review lands as APPROVED /
HUMAN_APPROVAL_REQUIRED. This is idempotent — the engine's
event log records `alreadyPresent: true` if satisfy is called
again after a prior successful call.

The other DEVELOPMENT exit criterion,
`quality.gates.passed`, is satisfied by
`/vibeflow:quality-gates` (Sprint 18-F) — orthogonal signal
(lint/typecheck/unit-tests rather than multi-AI review).

#### 3c.1 — Marker cleanup + follow-up (per-status)

1. If `status ∈ {APPROVED, NEEDS_REVISION}`, drain **both** markers:
   ```bash
   rm -f "$(vf_state_dir)/review-pending.json"
   rm -f "$(vf_state_dir)/consensus-needed.json"
   ```
   The second line is load-bearing: Sprint 16-A's `consensus-gate.sh`
   hook blocks every Bash/Write/Edit call while
   `consensus-needed.json` is present. If the orchestrator forgets to
   drain it, no further tool call (including the arbiter chain below)
   will succeed without operator bypass.
2. If `status == NEEDS_REVISION`, present the operator with BOTH
   downstream paths (Sprint 17-D/E) — the arbiter is still the
   default auto-chain, specialist is the opt-in deep-rewrite:
   ```
   /vibeflow:consensus-arbiter <session-id>
       — mechanical diff-first patches from reviewer suggestions[]
   /vibeflow:consensus-specialist <session-id>
       — phase-specific subagent deeply rewrites the artifact
         (PRD-rewriter for REQUIREMENTS, ADR-author for
         ARCHITECTURE, etc.) and emits one large diff-first patch
   ```
   Default behaviour is still to auto-chain the arbiter — it's
   conservative and mechanical. Specialist is invoked explicitly
   when reviewer feedback is structural enough that small patches
   won't cut it.
3. If `status == REJECTED`, do NOT auto-chain — leave the decision
   to the operator. Emit a short note citing the verdict path.
   **Still drain `consensus-needed.json`** (done in step 1) —
   REJECTED means the operator has been told; blocking every
   further tool call after that is pure friction.
4. If `status == HUMAN_APPROVAL_REQUIRED` (Sprint 17-C), emit a
   visible advisory naming the final agreement ratio and how to
   advance:
   ```
   N rounds exhausted without ≥ approvalThreshold agreement.
   Current agreement: <ratio>. Proceed with:
     /vibeflow:advance <next-phase> --humanOverrideNote "<reason>"
   Or run the specialist for a deep rewrite first:
     /vibeflow:consensus-specialist <session-id>
   ```

### Step 4: Consensus Calculation

**Available AIs:**
- 3 AIs: Normal consensus (weighted average)
- 2 AIs: 2-AI consensus (both must agree for APPROVED)
- 1 AI (Claude only): Single review with WARNING that consensus is degraded

**Scoring:**
```
consensusScore = weightedAverage(claudeScore, chatgptScore?, geminiScore?)
```

**Decision (use enum, NEVER string literals):**
```
if criticalDedup >= 2:
  status = "REJECTED"
elif rejected * 2 > total:         # Sprint 17-B: strict majority of REJECTED verdicts
  status = "REJECTED"
elif agreement >= approvalThreshold AND criticalDedup == 0:
  status = "APPROVED"
else:
  status = "NEEDS_REVISION"
```

Sprint 17-B: `criticalIssues` across reviewers is now **deduped** by
`{file, line_range}` equality OR by Jaccard similarity of the title
words (≥ 0.6). The pre-2.5.0 rule of `agreement < 0.5 → REJECTED`
was retired because it conflated "nobody approved" with "everyone
rejected" — three reviewers unanimously voting NEEDS_REVISION used
to fall through to REJECTED, skipping the arbiter. Now REJECTED
requires an explicit majority of reviewers to have actually
rejected.

### Step 5: Iterative Negotiation Rounds (Sprint 17-A)

When round-1 doesn't converge (not APPROVED, not REJECTED), re-run
the full reviewer panel in subsequent rounds with each reviewer
seeing the others' prior-round verdicts + top-3 critical findings
embedded in the prompt. Continues until one of:

1. **Early convergence** — `agreement ≥ consensus.approvalThreshold`
   (default 0.90) AND `criticalTotal == 0`. Status written as
   APPROVED.
2. **Max iterations reached** — configurable via
   `consensus.maxIterations` (default 5). At round N with no
   convergence, status becomes `HUMAN_APPROVAL_REQUIRED` (Sprint
   17-C, pass-with-audit) or stays NEEDS_REVISION/REJECTED
   according to the standard rules.
3. **Hard reject** — `criticalDedup ≥ ceil(quorum/2)` OR
   `agreement < 0.5`. Stops iteration immediately; status REJECTED.

**Configuration:**
- `consensus.maxIterations`: integer, default 5
- `consensus.approvalThreshold`: float, default 0.90
- `consensus.iteration.enabled`: boolean, default true. Set false
  to force single-round behaviour (rollback switch).

**Round marker:** before each round, write the integer round number
to `.vibeflow/state/consensus/<session>.current-round.txt`. The
aggregator reads this to tag each jsonl line with `round: N` and
filters aggregation to the current round only. `verdict.json`
accumulates a `rounds: [...]` array with one entry per finalised
round — the orchestrator reads this to decide whether to continue.

**Round N ≥ 2 prompt template:**

```
[original review prompt]

---

PRIOR ROUND (round N-1) VERDICT SUMMARY:

claude-reviewer (round N-1): <verdict>, score=<n>, critical=<n>
  Top findings:
  1. <title> — <one-line rationale>
  2. <title> — <one-line rationale>
  3. <title> — <one-line rationale>

codex (round N-1): <verdict>, score=<n>, critical=<n>
  Top findings: [same shape]

gemini (round N-1): <verdict>, score=<n>, critical=<n>
  Top findings: [same shape]

Overall agreement: <ratio>. Your own round N-1 verdict was
<verdict> — reconsider in light of the other reviewers' points.
Your new verdict should be one of APPROVED / NEEDS_REVISION /
REJECTED. Output ONLY JSON per the agreed schema.
```

Keep each reviewer's summary block ≤500 tokens — the full jsonl
remains on disk for arbiter/specialist downstream, the prompt only
carries the distilled signal.

**Iteration control pseudo-flow (orchestrator runs this after each
round's aggregator finalise):**

```bash
MAX_ROUNDS="$(vf_config_get '.consensus.maxIterations' || echo 5)"
THRESHOLD="$(vf_config_get '.consensus.approvalThreshold' || echo 0.90)"
ENABLED="$(vf_config_get '.consensus.iteration.enabled' || echo true)"

for round in $(seq 1 "$MAX_ROUNDS"); do
  echo "$round" > "$CONS_DIR/$SESSION_ID.current-round.txt"

  if [[ "$round" -gt 1 ]]; then
    # Build round-N prompt suffix from verdict.json.rounds[round-2]
    PRIOR_SUMMARY="$(jq -r --argjson r $((round-1)) '
      .rounds | map(select(.round == $r)) | .[0] // {}' \
      "$CONS_DIR/$SESSION_ID.verdict.json")"
    # Inject PRIOR_SUMMARY into the review prompt (≤500 tok / reviewer).
  fi

  # … run codex (timeout 90) → append_cli_verdict with $round
  # … run gemini (timeout 90) → append_cli_verdict with $round
  # … fork claude-reviewer (its SubagentStop fires aggregator)

  # Aggregator has now written verdict.json with rounds[round-1]
  STATUS="$(jq -r '.status' "$CONS_DIR/$SESSION_ID.verdict.json")"
  CRIT="$(jq -r '.criticalTotal' "$CONS_DIR/$SESSION_ID.verdict.json")"
  AGREE="$(jq -r '.agreement' "$CONS_DIR/$SESSION_ID.verdict.json")"

  # Early-stop checks
  if [[ "$STATUS" == "APPROVED" ]]; then
    iterationStopReason="earlyConverged"; break
  fi
  if [[ "$STATUS" == "REJECTED" ]]; then
    iterationStopReason="hardReject"; break
  fi
  if [[ "$ENABLED" != "true" ]]; then
    iterationStopReason="iterationDisabled"; break
  fi
done

if (( round >= MAX_ROUNDS )) && [[ -z "$iterationStopReason" ]]; then
  iterationStopReason="maxRounds"
  # Sprint 17-C: ambiguous-but-close → HUMAN_APPROVAL_REQUIRED
  if (( $(echo "$AGREE >= 0.5" | bc -l) )); then
    jq '.status = "HUMAN_APPROVAL_REQUIRED"' \
      "$CONS_DIR/$SESSION_ID.verdict.json" > /tmp/v && \
      mv /tmp/v "$CONS_DIR/$SESSION_ID.verdict.json"
  fi
fi

# Update verdict.json with the stop reason.
jq --arg r "$iterationStopReason" '.iterationStopReason = $r' \
  "$CONS_DIR/$SESSION_ID.verdict.json" > /tmp/v && \
  mv /tmp/v "$CONS_DIR/$SESSION_ID.verdict.json"

# Clean up the round marker — future single-round invocations on
# the same session should start from round 1 again.
rm -f "$CONS_DIR/$SESSION_ID.current-round.txt"
```

### Step 5b: Single-round fallback

If `consensus.iteration.enabled` is false, or the config is missing,
or the orchestrator is run on a host without `bc` / `jq`, the loop
falls through to round 1 only. The aggregator still writes a valid
`rounds: [{round:1, …}]` array — downstream consumers don't change.

## Output Format
```markdown
# Consensus Review Report

## Decision: [APPROVED | NEEDS_REVISION | REJECTED]
## Consensus Score: XX/100
## AIs Participating: X/3

## Individual Reviews
### Claude (score: XX/100)
[Summary and key findings]

### ChatGPT (score: XX/100) [or "Not available"]
[Summary and key findings]

### Gemini (score: XX/100) [or "Not available"]
[Summary and key findings]

## Aggregated Issues
### Critical
[Merged and deduplicated critical issues]

### High
[...]

## Consensus Notes
[Any disagreements, negotiation rounds, or degradation warnings]
```
