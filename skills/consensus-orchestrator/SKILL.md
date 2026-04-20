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

  jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg reviewer "$reviewer" \
    --arg verdict "$verdict" \
    --argjson critical "$critical" \
    --arg note "$note" \
    --argjson raw "$(printf '%s' "$raw" | jq -Rsr 'try fromjson catch {}' 2>/dev/null || echo '{}')" \
    '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical, note:$note, suggestions:($raw.suggestions // [])}' \
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

### Step 3c: Post-consensus cleanup (Sprint 15-A, 16-B)

Once the aggregator has written `.vibeflow/state/consensus/<session>.verdict.json`:

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
2. If `status == NEEDS_REVISION`, chain into the arbiter:
   ```
   /vibeflow:consensus-arbiter <session-id>
   ```
   The arbiter reads each reviewer's `suggestions[]` + the current
   phase + domain, decides per-suggestion which apply now vs defer
   vs reject, and emits diff-first patches under
   `.vibeflow/state/patches/<session>/` without touching source
   files. Apply with `/vibeflow:apply-arbiter-patch`.
3. If `status == REJECTED`, do NOT auto-chain — leave the decision
   to the operator. Emit a short note citing the verdict path.
   **Still drain `consensus-needed.json`** (done in step 1) —
   REJECTED means the operator has been told; blocking every
   further tool call after that is pure friction.

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
if consensusScore >= 90 AND criticalIssues == 0:
  status = "APPROVED"      // Always UPPERCASE
elif consensusScore < 50 OR criticalIssues >= 2:
  status = "REJECTED"      // Always UPPERCASE (fixes Bug #1!)
else:
  status = "NEEDS_REVISION" // Always UPPERCASE
```

### Step 5: Disagreement Resolution
If AIs disagree significantly (>30 point spread):
1. Round 1: Share each AI's review with the others
2. Round 2: Each AI reconsiders with full context
3. Round 3: If still no consensus, escalate to human

Max 3 negotiation rounds. After that: human decision required.

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
