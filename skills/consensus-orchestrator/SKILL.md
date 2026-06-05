---
name: consensus-orchestrator
description: Orchestrates multi-AI review process. Coordinates Claude, ChatGPT (codex CLI), and Gemini (gemini CLI) reviews. Each CLI's verdict is appended to the session jsonl the aggregator reads, per-CLI 90s timeout so the aggregator never falls through to its 600s global wait. On NEEDS_REVISION verdicts the skill auto-invokes consensus-arbiter to decide which reviewer suggestions are applicable to the current phase.
disable-model-invocation: true
allowed-tools: Read Write Bash(codex *) Bash(gemini *) Bash(jq *) Bash(timeout *) Bash(gtimeout *) Bash(sleep *) Bash(kill *) Bash(touch *) Bash(rm *) Bash(mkdir *) Grep Glob
---

# Consensus Orchestrator

Manages the multi-AI review cycle that replaces MyVibe's CLI subprocess approach. Fixes Bug #1 (case mismatch), Bug #2 (model names), and Bug #8 (no CLI fallback).

> **Interactive vs headless (Sprint 31-C).** This skill is the full
> **interactive** path: it forks the `claude-reviewer` subagent as a third
> reviewer and that subagent's SubagentStop fires
> `consensus-aggregator.sh`, plus it runs iterative negotiation rounds
> (Step 5) and records consensus / chains the arbiter. It is
> `disable-model-invocation: true`, so the model cannot fork it — the
> operator runs it via the slash command.
>
> `hooks/scripts/consensus-run.sh` is the **headless equivalent** that
> `/vibeflow:phase-runner` calls as plain Bash: it runs the same codex /
> gemini reviewer CLIs and finalises the same `verdict.json` (via
> `consensus-aggregator.sh --finalize`), but without claude-reviewer
> (model-only) and without the iteration loop — a real codex+gemini panel.
> Use it when you want a one-command verdict; use this skill when you want
> the full 3-AI iterative review. Both feed the same history.jsonl /
> reviewer-memory / auto-revert machinery.

## Input
- $ARGUMENTS: Path to artifact(s) to review, or "review last commit"
- vibeflow.config.json: model names, domain

## Consensus Flow

### Step 1: Read Configuration
```
openaiModel = vibeflow.config.json.models.openai   // "default" / unset → omit -m
geminiModel = vibeflow.config.json.models.gemini    // "default" / unset → omit --model
```

**Model resolution.** When `models.openai` / `models.gemini` is `"default"`,
empty, or unset, do **NOT** pass `-m` / `--model` — let codex (`~/.codex/config.toml`)
and gemini use their own configured model. A hardcoded id (the old `gpt-4o` /
`gemini-2.0-flash` defaults) is account/CLI-version-specific and silently
fails when the login doesn't accept it. Only pass the flag when the operator
pinned a concrete id. (The headless sibling `hooks/scripts/consensus-run.sh`
implements exactly this — keep them in step.)

> **errexit caution.** `_lib.sh` declares `set -euo pipefail`. If you source
> it, run `set +e` before the reviewer-CLI calls below: they rely on
> `OUT="$(codex …)"; RC=$?` and under errexit a non-zero CLI aborts the run
> at the assignment, before the rc is read.

**Note (Sprint 14-A):** There is no `mode` concept anymore. Every
reviewer participation is decided by CLI availability — codex and
gemini join the panel when their CLIs are on `PATH`, full stop. Both
CLIs use the operator's own authenticated session, so there is no
API billing concern to gate on.

### Step 2: Claude Review (Always Available)
Use the claude-reviewer subagent for native review. This always runs.

### Step 2b: Resolve the review input (Sprint 19-B — primaryArtifact)

Before spawning any reviewer, resolve what the panel is actually
reviewing. `$ARGUMENTS` may be:

1. **A marker JSON path** (`.vibeflow/state/consensus-needed.json`
   or a file whose content includes a `primaryArtifact` field) —
   the Sprint 19-A marker schema v2 case.
2. **A plain file path** — legacy single-file invocation
   (pre-v2.7.0). Treated as the primary with no evidence.

```bash
# Marker v2 resolution
if jq -e '.primaryArtifact' "$ARGUMENTS" >/dev/null 2>&1; then
  PRIMARY="$(jq -r '.primaryArtifact' "$ARGUMENTS")"
  mapfile -t EVIDENCE_FILES < <(jq -r '.evidence[]?' "$ARGUMENTS" 2>/dev/null)
else
  PRIMARY="$ARGUMENTS"   # legacy path — full file content is the primary
  EVIDENCE_FILES=()
fi

[ -f "$PRIMARY" ] || { echo "primary artifact not found: $PRIMARY"; exit 1; }
```

**Primary excerpt when too large (Sprint 21-A — semantic).** If
`wc -c "$PRIMARY"` exceeds `consensus.excerptTokenBudget` (default
30 000 tokens ≈ 120 KB), excerpt the primary for the reviewer prompt.
The strategy is `consensus.excerptStrategy` (default `semantic`;
`headtail` forces the legacy positional behaviour).

`semantic` is **section-scored selection** — feed reviewers the
sections that matter, not the sections that happen to be at the top:

1. **Split** the primary into sections by markdown headings
   (`^#{1,6} `) — and by form-feed / page breaks for `.docx`-derived
   text. A doc with **no detectable section structure falls back** to
   the head-40% / tail-15% positional excerpt below (never worse than
   the legacy path).
2. **Score** each section (see `references/excerption.md` for the
   exact formula):
   - **evidence-finding density** — count of evidence findings whose
     `target.line_range` / quoted text lands in the section;
   - **reviewer-memory hits** — section text matching prior `criticals`
     from this artifact's Sprint 20-D memory store (reuse the signal
     the loop already has — contested sections score higher);
   - **evidence-summary keyword overlap** — Jaccard(section words,
     distilled-evidence words).
3. **Select** the first section (title/overview) **always**, then fill
   the remaining budget with the highest-scored sections, emitted in
   **document order** so reviewers read a coherent doc.
4. Append the same **findings-anchored ±20-line windows** as before for
   any top-priority finding whose section didn't make the cut.

`headtail` (and the no-sections fallback): first 40% (head) + last 15%
(tail) + findings-anchored ±20-line windows.

Smaller primaries go in whole. The specialist path (if triggered
downstream) always receives the full file; excerption only affects
the reviewer prompt.

**Evidence distillation.** For each evidence file, extract:

- First heading + verdict line
- Top 3 critical / high findings (ordered by severity)
- Any `Summary` / `Aggregate` section

Inline as a ≤500-token block per evidence source in the reviewer
prompt (see Step 3 below).

### Step 3: External AI Reviews (CLI-availability only)
Run every CLI that is on `PATH`. Skip the ones that aren't — never
gate on a mode switch, environment variable, or config flag.

**Reviewer prompt shape (Sprint 19-B).** Every reviewer (codex,
gemini, claude-reviewer) receives the same structure — `PRIMARY`
is the thing under review, `EVIDENCE` is context:

```
Review the PRIMARY ARTIFACT below for quality/security/maintainability.
Your verdict decides whether this artifact is ready for phase exit.

PRIMARY ARTIFACT UNDER REVIEW:
<$PRIMARY content, excerpted per Step 2b if > 30k tokens>

SUPPORTING EVIDENCE (analyzer context — informational, not the target):
1. <EVIDENCE_FILES[0] filename>:
   <distilled ≤500 tokens: verdict line + top-3 findings>
2. <EVIDENCE_FILES[1] filename>:
   <distilled>
...

Your verdict is about the PRIMARY, not the evidence reports.
Output ONLY valid JSON per the agreed schema.
```

**ChatGPT Review (via codex CLI):**

> ⚠️ **Sprint 26-G — always PIPE the prompt to `codex exec`; never pass
> it as an argument.** The argument form (`codex exec "$PROMPT"`) leaves
> stdin open, so `codex exec` blocks waiting for stdin EOF and **hangs
> indefinitely** (observed: 51-minute hangs in a real consumer). Piping
> the prompt closes stdin (EOF) and codex returns normally. The full
> invocation in Step 3 (`build_review_prompt | vf_run_timeout 90 codex
> exec …`) is the canonical, EOF-safe form — this example mirrors it.

```bash
if command -v codex &>/dev/null; then
  # PIPE the prompt → stdin EOF. The argument form hangs (open stdin).
  build_review_prompt | codex exec -m $openaiModel --skip-git-repo-check --ephemeral
fi
```

**Gemini Review (via gemini CLI):**
```bash
if command -v gemini &>/dev/null; then
  build_review_prompt | gemini --model $geminiModel
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

# Sprint 20-A: persist the resolved primary-artifact path (from Step 2b)
# as a sidecar the aggregator reads when it appends the cross-session
# `history.jsonl` row. The aggregator runs as a SubagentStop hook and
# has no other channel to learn what the panel actually reviewed.
# Cleaned up alongside the round marker at the end of Step 5.
printf '%s\n' "$PRIMARY" > "$CONS_DIR/$SESSION_ID.primary.txt"

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

# Sprint 20-E: render a bounded PRIOR REVIEW MEMORY block for ONE
# reviewer, scoped to the current $PRIMARY. Reads the Sprint 20-D
# store (`reviewer-memory/<reviewer>.jsonl`). Emits NOTHING on a clean
# first run (no store, or no entries for this artifact) so round-1
# prompts are byte-identical to pre-Sprint-20. Honours
# `reviewerMemory.tokenBudget` (chars ≈ tokens × 4) and
# `reviewerMemory.enabled=false` (kill switch). Closes the
# "reviewers have amnesia" gap: a reviewer is reminded what it raised
# last round / last sprint so it stops re-litigating resolved points
# and escalates genuine recurrences.
build_memory_block() {
  local rv="$1"
  [[ "$(vf_config_get '.reviewerMemory.enabled' 2>/dev/null || echo true)" == "false" ]] && return 0
  local mem="$CONS_DIR/reviewer-memory/$rv.jsonl"
  [[ -f "$mem" ]] || return 0
  local budget; budget="$(vf_config_get '.reviewerMemory.tokenBudget' 2>/dev/null || echo 600)"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=600
  # Sprint 21-B: render the theme-aware recurrence summary FIRST
  # (highest seenCount → a long-standing unresolved objection leads the
  # block), then the most-recent detail entries. A "recency"-mode store
  # simply has no summary row, so this degrades to recent-detail only.
  local body
  body="$(jq -s -r --arg primary "$PRIMARY" '
    map(select(.primaryArtifact == $primary)) as $rows
    | (($rows | map(select(.type == "summary")) | .[0]) // null) as $sum
    | ($rows | map(select(.type != "summary")) | reverse) as $details
    | (
        (if $sum then (($sum.recurringCriticals // []) | sort_by(-.seenCount)
           | map("- RECURRING (seen \(.seenCount)×): \(.title)")) else [] end)
        + ($details | map("- [round \(.round) · \(.status)] \((.criticals // []) | join("; "))"))
      ) | .[]' \
    "$mem" 2>/dev/null || true)"
  [[ -n "$body" ]] || return 0
  body="$(printf '%s' "$body" | head -c "$(( budget * 4 ))")"
  cat <<MEM
PRIOR REVIEW MEMORY ($rv on $PRIMARY):
You have reviewed this artifact before. Previously you raised:
$body

Verify whether these were addressed. Do NOT re-raise resolved items;
escalate (raise as critical) any that recur unaddressed.
---
MEM
}

# Sprint 21-A: excerpt the primary for the reviewer prompt when it
# exceeds consensus.excerptTokenBudget (chars ≈ tokens × 4). Strategy
# is consensus.excerptStrategy ("semantic" default | "headtail"). The
# specialist path always gets the full file — this only shapes what
# reviewers read. See references/excerption.md for the scoring formula.
excerpt_if_large() {
  local f="$1"
  local budget; budget="$(vf_config_get '.consensus.excerptTokenBudget' 2>/dev/null || echo 30000)"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=30000
  local maxchars=$(( budget * 4 ))
  local bytes; bytes="$(wc -c < "$f" 2>/dev/null || echo 0)"
  if (( bytes <= maxchars )); then cat "$f"; return 0; fi   # small → whole

  local strategy; strategy="$(vf_config_get '.consensus.excerptStrategy' 2>/dev/null || echo semantic)"
  # Section split on markdown headings + form-feed page breaks.
  local sections; sections="$(grep -cE '^#{1,6} |\f' "$f" 2>/dev/null || echo 0)"
  if [[ "$strategy" == "semantic" ]] && (( sections >= 2 )); then
    # Score each section by evidence-finding density + reviewer-memory
    # hits + evidence-keyword Jaccard; ALWAYS include section 1; fill
    # the budget with the top-scored sections in document order; append
    # findings-anchored ±20-line windows for any uncut top finding.
    # (Implemented per references/excerption.md; emits the selected
    # sections to stdout.)
    vf_excerpt_semantic "$f" "$maxchars"
  else
    # headtail (and the no-sections fallback): head 40% + tail 15%
    # + findings-anchored windows.
    vf_excerpt_headtail "$f" "$maxchars"
  fi
}

# Sprint 19-B: build the PRIMARY + EVIDENCE review prompt once and
# feed it to both CLIs. See Step 2b for $PRIMARY / $EVIDENCE_FILES
# resolution. The prompt structure names PRIMARY ARTIFACT UNDER
# REVIEW explicitly so reviewers know the evidence reports are
# context, not targets. Sprint 20-E prepends each reviewer's own
# PRIOR REVIEW MEMORY block (per-reviewer, so it can't be baked into
# this shared builder — it is concatenated at each CLI call below).
build_review_prompt() {
  cat <<PROMPT
Review the PRIMARY ARTIFACT below for quality/security/maintainability.
Your verdict decides whether this artifact is ready for phase exit.
Output ONLY valid JSON matching: {verdict:APPROVED|NEEDS_REVISION|REJECTED,
score:0-100, criticalIssues:[{id, target:{file, line_range:[s,e]}, title, rationale}],
summary:string, suggestions:[{id, type, target:{file, line_range:[s,e]},
rationale, proposed_change, priority, phase_relevance:[]}]}

PRIMARY ARTIFACT UNDER REVIEW ($PRIMARY):
$(excerpt_if_large "$PRIMARY")

SUPPORTING EVIDENCE (analyzer context — informational, not the target):
$(for e in "\${EVIDENCE_FILES[@]}"; do echo "--- $e ---"; distill_evidence "$e"; done)

Your verdict is about the PRIMARY, not the evidence reports.
PROMPT
}

# Sprint 26-F: portable 90s timeout. macOS ships NO `timeout` binary, so a
# bare call fails with `command not found` (rc 127) on every invocation →
# every CLI gets recorded as cli_error/REJECTED and consensus can never use
# the external reviewers on stock macOS. Prefer GNU `timeout`,
# then `gtimeout` (coreutils), else a pure-bash watchdog. The watchdog
# returns 124 on its own kill so the existing `(( RC == 124 ))` cli_timeout
# branch handles all three uniformly.
vf_run_timeout() {   # vf_run_timeout <seconds> <cmd...>   (forwards stdin)
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  # Pure-bash fallback. CRITICAL: a backgrounded command (`cmd &`) gets its
  # stdin from /dev/null by POSIX rule — which would feed codex/gemini an
  # EMPTY prompt. Drain the piped prompt to a temp file first and redirect
  # the child's stdin from it explicitly so the prompt survives.
  local _in; _in="$(mktemp)"; cat > "$_in"
  "$@" < "$_in" & local pid=$!
  # Watchdog. CRITICAL: redirect its stdout/stderr to /dev/null. Inside a
  # `CMD="$( … | vf_run_timeout … )"` capture the backgrounded subshell
  # inherits the command-substitution's stdout pipe; if it (or its `sleep`
  # child) holds that fd open, `$( … )` blocks until `sleep $secs` ends —
  # a full 90s hang AFTER the CLI already returned. The redirect drops the
  # pipe fd so the capture closes the instant the CLI exits.
  ( sleep "$secs"; kill -0 "$pid" 2>/dev/null && { touch "/tmp/vf_to_$pid"; kill -TERM "$pid" 2>/dev/null; }; ) >/dev/null 2>&1 & local wd=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill -TERM "$wd" 2>/dev/null; pkill -P "$wd" 2>/dev/null; wait "$wd" 2>/dev/null; rm -f "$_in"
  if [[ -f "/tmp/vf_to_$pid" ]]; then rm -f "/tmp/vf_to_$pid"; return 124; fi
  return "$rc"
}

# codex — 90s per-CLI timeout so aggregator never sits on its 600s global wait.
if command -v codex >/dev/null 2>&1; then
  CODEX_OUT="$( { build_memory_block codex; build_review_prompt; } | vf_run_timeout 90 codex exec -m "$openaiModel" --skip-git-repo-check --ephemeral 2>&1)"
  CODEX_RC=$?
  if (( CODEX_RC == 124 )); then
    append_cli_verdict codex '{"verdict":"REJECTED","criticalIssues":0}' "cli_timeout"
  elif (( CODEX_RC != 0 )); then
    append_cli_verdict codex '{"verdict":"REJECTED","criticalIssues":0}' "cli_error:$CODEX_RC"
  else
    append_cli_verdict codex "$CODEX_OUT" ""
  fi
fi

# gemini — same shape. Shares build_review_prompt so both CLIs see
# the same PRIMARY + EVIDENCE framing.
if command -v gemini >/dev/null 2>&1; then
  GEMINI_OUT="$( { build_memory_block gemini; build_review_prompt; } | vf_run_timeout 90 gemini --model "$geminiModel" 2>&1)"
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

**Sprint 20-E (claude-reviewer memory):** prepend the same PRIOR REVIEW
MEMORY block to the claude-reviewer subagent prompt, resolved with
`build_memory_block claude-reviewer` (the reviewer name in the Sprint
20-D store matches the subagent name). On a clean first run the helper
emits nothing, so the subagent prompt is unchanged.

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

  # … run codex (vf_run_timeout 90) → append_cli_verdict with $round
  # … run gemini (vf_run_timeout 90) → append_cli_verdict with $round
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
# the same session should start from round 1 again. The Sprint 20-A
# primary sidecar is dropped here too (the history rows are already
# persisted; the sidecar is only needed during the live round loop).
rm -f "$CONS_DIR/$SESSION_ID.current-round.txt" \
      "$CONS_DIR/$SESSION_ID.primary.txt"
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
