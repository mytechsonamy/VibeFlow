#!/bin/bash
# VibeFlow Headless Consensus Runner (Sprint 31-C).
#
# The non-interactive equivalent of the `/vibeflow:consensus-orchestrator`
# skill's external-CLI pipeline. The orchestrator skill is the full
# INTERACTIVE path: it forks the `claude-reviewer` subagent (a model
# action) as a third reviewer, and that subagent's SubagentStop event is
# what fires `consensus-aggregator.sh` to finalize the verdict.
#
# A skill marked `disable-model-invocation: true` (orchestrator,
# specialist, arbiter, apply, advance) CANNOT be forked by the model, so
# `phase-runner` could never drive consensus on its own — it deadlocked
# (analyzer writes consensus-needed.json → consensus-gate blocks every
# subsequent tool call → the chain that drains the marker is un-forkable).
#
# This script closes that gap. Invoked directly as plain Bash by
# phase-runner, it:
#   1. resolves the primary artifact (marker-v2 or plain path),
#   2. runs every external reviewer CLI on PATH (codex, gemini),
#   3. finalizes a real verdict.json via `consensus-aggregator.sh
#      --finalize` (no 600s quorum stall — the panel is exactly the CLIs
#      that ran), feeding the same history.jsonl / reviewer-memory /
#      auto-revert machinery the interactive path uses,
#   4. drains consensus-needed.json so the gate unblocks.
#
# It does NOT call the `sdlc_record_consensus` MCP tool (a model action) —
# the caller (phase-runner) reads verdict.json and records consensus +
# satisfies criteria itself.
#
# claude-reviewer is intentionally absent here: a shell script cannot
# produce a native Claude review. With codex+gemini on PATH this is a
# real 2-AI panel (the aggregator's documented "2 AIs: both must agree for
# APPROVED" mode). For the full 3-AI panel + iterative negotiation, use the
# interactive `/vibeflow:consensus-orchestrator`.
#
# Usage: consensus-run.sh <primaryArtifact|markerPath>
# Exit:  0 = verdict.json written (status on stdout), 1 = setup error,
#        3 = no external reviewer CLI on PATH (caller should fall back to
#            the interactive orchestrator, which always has claude-reviewer).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# CRITICAL: _lib.sh declares `set -euo pipefail`, so sourcing it leaks
# errexit into THIS script. consensus-run is built to *capture* reviewer
# CLI exit codes (`OUT="$(codex …)"; RC=$?`) and keep going — under errexit
# a single non-zero CLI would abort the run at the assignment, BEFORE the
# rc is read, so the cli_error/cli_timeout handling never fires and no
# verdict is produced. Re-disable errexit (keep nounset + pipefail).
set +e

ARG="${1:-}"
if [[ -z "$ARG" ]]; then
  echo "consensus-run: missing argument — pass the primary artifact path or a consensus-needed.json marker" >&2
  exit 1
fi
if ! vf_have_jq; then
  echo "consensus-run: jq is required" >&2
  exit 1
fi

# --- Step 1: resolve the primary artifact (marker v2 or plain path) -------
# Mirrors consensus-orchestrator Step 2b. bash 3.2 compatible (no mapfile).
EVIDENCE_FILES=()
if jq -e '.primaryArtifact' "$ARG" >/dev/null 2>&1; then
  PRIMARY="$(jq -r '.primaryArtifact' "$ARG")"
  while IFS= read -r _e; do
    [[ -n "$_e" ]] && EVIDENCE_FILES+=("$_e")
  done < <(jq -r '.evidence[]?' "$ARG" 2>/dev/null)
else
  PRIMARY="$ARG"   # legacy plain path — whole file is the primary
fi

if [[ ! -f "$PRIMARY" ]]; then
  echo "consensus-run: primary artifact not found: $PRIMARY" >&2
  exit 1
fi

# Bail early if there is no external reviewer to run — a headless panel
# needs at least one CLI. The caller falls back to the interactive
# orchestrator (which always has claude-reviewer).
if ! command -v codex >/dev/null 2>&1 && ! command -v gemini >/dev/null 2>&1; then
  echo "consensus-run: no external reviewer CLI (codex/gemini) on PATH" >&2
  exit 3
fi

openaiModel="$(vf_config_get '.models.openai' 2>/dev/null || echo '')"
[[ "$openaiModel" == "null" ]] && openaiModel=''
geminiModel="$(vf_config_get '.models.gemini' 2>/dev/null || echo '')"
[[ "$geminiModel" == "null" ]] && geminiModel=''
# Build the model flag ONLY when explicitly pinned. Empty / "default" /
# "null" → omit it and let each CLI use its OWN configured model
# (codex: ~/.codex/config.toml; gemini: its built-in default). This is
# immune to stale hardcoded defaults and to per-account model availability —
# a fixed "gpt-4o" / "gemini-2.0-flash" was exactly what silently broke
# headless consensus when the account/CLI didn't accept it. Model ids are
# safe single tokens, so the unquoted expansion below splits cleanly.
CODEX_MFLAG=""
case "$openaiModel" in ""|default) : ;; *) CODEX_MFLAG="-m $openaiModel" ;; esac
GEMINI_MFLAG=""
case "$geminiModel" in ""|default) : ;; *) GEMINI_MFLAG="--model $geminiModel" ;; esac

SESSION_ID="${CLAUDE_SESSION_ID:-headless-$(date -u +%s)-$$}"
STATE_DIR="$(vf_state_dir)"
CONS_DIR="$STATE_DIR/consensus"
mkdir -p "$CONS_DIR"
LOG="$CONS_DIR/$SESSION_ID.jsonl"
ROUND=1

# Round marker + primary sidecar — the aggregator reads both at finalize
# (round tag on each jsonl line + history.jsonl primaryArtifact).
printf '%s\n' "$ROUND" > "$CONS_DIR/$SESSION_ID.current-round.txt"
printf '%s\n' "$PRIMARY" > "$CONS_DIR/$SESSION_ID.primary.txt"

# --- helpers (lifted from consensus-orchestrator Step 3, now executable) --

# Portable per-CLI timeout (Sprint 26-F): macOS ships no `timeout`. Prefer
# GNU timeout → gtimeout → pure-bash watchdog (returns 124 on kill). The
# watchdog drains the piped prompt to a temp file so the child's stdin
# isn't the POSIX /dev/null a backgrounded job would otherwise get.
vf_run_timeout() {   # vf_run_timeout <seconds> <cmd...>   (forwards stdin)
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  local _in; _in="$(mktemp)"; cat > "$_in"
  "$@" < "$_in" & local pid=$!
  # Watchdog. CRITICAL: redirect its stdout/stderr to /dev/null. When this
  # runs inside `CMD="$( … | vf_run_timeout … )"`, a backgrounded subshell
  # inherits the command-substitution's stdout pipe; if it (or its `sleep`
  # child) keeps that fd open, `$( … )` blocks until `sleep $secs` ends —
  # a full 90s hang AFTER the CLI already returned. The redirect drops the
  # pipe fd so the substitution closes as soon as the CLI exits.
  ( sleep "$secs"; kill -0 "$pid" 2>/dev/null && { touch "/tmp/vf_to_$pid"; kill -TERM "$pid" 2>/dev/null; }; ) >/dev/null 2>&1 & local wd=$!
  # disown so the shell doesn't print a "Terminated" job notice when we kill
  # the watchdog below (the CLI finished early — the common case).
  disown "$wd" 2>/dev/null
  wait "$pid" 2>/dev/null; local rc=$?
  # Tear down the watchdog AND its sleep child so nothing lingers.
  kill -TERM "$wd" 2>/dev/null; pkill -P "$wd" 2>/dev/null; rm -f "$_in"
  if [[ -f "/tmp/vf_to_$pid" ]]; then rm -f "/tmp/vf_to_$pid"; return 124; fi
  return "$rc"
}

# Large primaries: head/tail byte budget so a giant PRD doesn't blow the
# CLI prompt. (Headless keeps it simple — the interactive orchestrator has
# the Sprint 21-A semantic excerpter; the specialist path always gets the
# full file regardless.)
excerpt_primary() {
  local f="$1" budget maxchars bytes
  budget="$(vf_config_get '.consensus.excerptTokenBudget' 2>/dev/null || echo 30000)"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=30000
  maxchars=$(( budget * 4 ))
  bytes="$(wc -c < "$f" 2>/dev/null || echo 0)"
  if (( bytes <= maxchars )); then cat "$f"; return 0; fi
  head -c $(( maxchars * 70 / 100 )) "$f"
  printf '\n\n...[%s truncated for review — full file preserved on disk]...\n\n' "$f"
  tail -c $(( maxchars * 15 / 100 )) "$f"
}

distill_evidence() {  # first heading + verdict line + a few findings
  local e="$1"
  [[ -f "$e" ]] || { echo "(evidence not found: $e)"; return 0; }
  grep -m1 -E '^#' "$e" 2>/dev/null || true
  grep -m1 -iE 'verdict|status|score' "$e" 2>/dev/null || true
  grep -m3 -iE 'critical|high' "$e" 2>/dev/null || true
}

build_review_prompt() {
  cat <<PROMPT
Review the PRIMARY ARTIFACT below for quality/security/maintainability.
Your verdict decides whether this artifact is ready for phase exit.
Output ONLY valid JSON matching: {verdict:APPROVED|NEEDS_REVISION|REJECTED,
score:0-100, criticalIssues:[{id, target:{file, line_range:[s,e]}, title, rationale}],
summary:string, suggestions:[{id, type, target:{file, line_range:[s,e]},
rationale, proposed_change, priority, phase_relevance:[]}]}

PRIMARY ARTIFACT UNDER REVIEW ($PRIMARY):
$(excerpt_primary "$PRIMARY")

SUPPORTING EVIDENCE (analyzer context — informational, not the target):
$(for e in "${EVIDENCE_FILES[@]:-}"; do [[ -n "$e" ]] || continue; echo "--- $e ---"; distill_evidence "$e"; done)

Your verdict is about the PRIMARY, not the evidence reports.
PROMPT
}

# Emit the FIRST balanced `{…}` object from stdin — brace-counting that
# ignores braces inside JSON strings + handles escapes. Robust where a greedy
# first-`{`…last-`}` span over-captures: codex CLI 0.135.0 `exec` mode prints
# the verdict JSON TWICE (body + trailing echo) with a `tokens used\nN` line
# wedged between, and the greedy span swallowed both objects + that junk →
# invalid JSON → the rationale was discarded anyway. Balanced extraction takes
# just the first complete object.
_vf_first_json_object() {
  awk '
    { buf = buf $0 "\n" }
    END {
      s = buf; n = length(s); depth = 0; instr = 0; esc = 0; start = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (start == 0) { if (c == "{") { start = i; depth = 1 } ; continue }
        if (esc) { esc = 0; continue }
        if (c == "\\") { esc = 1; continue }
        if (instr) { if (c == "\"") instr = 0 ; continue }
        if (c == "\"") { instr = 1; continue }
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) { print substr(s, start, i - start + 1); exit } }
      }
    }'
}

# Extract a JSON object from a reviewer CLI's raw output. codex/gemini wrap the
# verdict JSON in prose or a ```json fence (and codex 0.135.0 emits it twice),
# so a whole-output `fromjson` FAILS and the structured verdict (criticalIssues
# + suggestions) is silently lost — the reviewer's dissent collapses to an
# actionless keyword-grep NEEDS_REVISION (the FlowBridge/AntOS "codex gives no
# rationale, the specialist→apply loop runs blind" bug). Strategy: try the
# whole output → strip code fences → take the first BALANCED object. Emits the
# JSON on stdout (empty + rc1 if nothing parseable).
vf_extract_json() {
  local raw; raw="$(cat)"
  if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then printf '%s' "$raw"; return 0; fi
  local nf; nf="$(printf '%s\n' "$raw" | sed '/^[[:space:]]*```/d')"
  if printf '%s' "$nf" | jq -e . >/dev/null 2>&1; then printf '%s' "$nf"; return 0; fi
  local obj; obj="$(printf '%s' "$nf" | _vf_first_json_object)"
  if [[ -n "$obj" ]] && printf '%s' "$obj" | jq -e . >/dev/null 2>&1; then printf '%s' "$obj"; return 0; fi
  return 1
}

# Append one reviewer's verdict line to the session jsonl in the exact
# shape consensus-aggregator.sh expects (see its lines 140-148).
append_cli_verdict() {
  local reviewer="$1" raw="$2" note="${3:-}"
  local verdict critical critical_items json structured
  # Pull the structured JSON out of any prose / markdown wrapping FIRST, so a
  # wrapped verdict still yields criticalIssues + suggestions (not just a
  # keyword-grep verdict with empty rationale). Falls back to {} when the
  # reviewer truly emitted no JSON — the keyword grep below still classifies.
  json="$(printf '%s' "$raw" | vf_extract_json 2>/dev/null || true)"
  [[ -n "$json" ]] || json='{}'
  structured="$(printf '%s' "$json" | jq -r 'try .verdict catch empty' 2>/dev/null || true)"
  case "$structured" in
    APPROVED|NEEDS_REVISION|REJECTED) verdict="$structured" ;;
    *)
      if echo "$raw" | grep -qE 'REJECTED'; then verdict=REJECTED
      elif echo "$raw" | grep -qE 'NEEDS_REVISION|NEEDS[[:space:]]REVISION'; then verdict=NEEDS_REVISION
      elif echo "$raw" | grep -qE 'APPROVED'; then verdict=APPROVED
      else verdict=NEEDS_REVISION
      fi
      ;;
  esac
  critical="$(printf '%s' "$json" | jq -r 'try (.criticalIssues | if type=="array" then length else . end) catch 0' 2>/dev/null || echo 0)"
  [[ "$critical" =~ ^[0-9]+$ ]] || critical=0
  critical_items="$(printf '%s' "$json" | jq -c 'try (.criticalIssues | if type=="array" then . else [] end) catch []' 2>/dev/null || echo "[]")"
  printf '%s' "$critical_items" | jq -e . >/dev/null 2>&1 || critical_items="[]"
  jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg reviewer "$reviewer" \
    --arg verdict "$verdict" \
    --argjson critical "$critical" \
    --argjson criticalItems "$critical_items" \
    --arg note "$note" \
    --argjson round "$ROUND" \
    --argjson raw "$json" \
    '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical, criticalItems:$criticalItems, round:$round, note:$note, suggestions:($raw.suggestions // [])}' \
    >> "$LOG"
}

# --- Step 2: run the external reviewer CLIs (those on PATH) ---------------
# A CLI that ERRORS (non-zero, e.g. a bad model id / auth) is NOT a review —
# we warn loudly (naming the model + the config key to fix) and skip it, so
# a misconfigured reviewer can't poison the panel with a phantom REJECTED
# vote. A CLI that TIMES OUT did participate but didn't converge → counts as
# a conservative REJECTED (mirrors the interactive orchestrator).
ERRORS=0
warn_cli_error() {  # <name> <rc> <model-label> <config-key> <output>
  local name="$1" rc="$2" mdl="$3" key="$4" out="$5"
  echo "consensus-run: $name FAILED (rc=$rc, model: ${mdl:-<CLI default>}) — NOT counted as a review." >&2
  echo "  → Check '$key' in vibeflow.config.json. Your $name login/CLI may not accept that model;" >&2
  echo "    set '$key' to \"default\" to defer to the CLI's own configured model, or pin a valid id." >&2
  [[ -n "$out" ]] && echo "  → $name said: $(printf '%s' "$out" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-300)" >&2
}

if command -v codex >/dev/null 2>&1; then
  CODEX_OUT="$( build_review_prompt | vf_run_timeout 90 codex exec $CODEX_MFLAG --skip-git-repo-check --ephemeral 2>&1 )"
  CODEX_RC=$?
  if (( CODEX_RC == 124 )); then
    echo "consensus-run: codex timed out after 90s (model: ${openaiModel:-<CLI default>})" >&2
    append_cli_verdict codex '{"verdict":"REJECTED","criticalIssues":0}' "cli_timeout"
  elif (( CODEX_RC != 0 )); then
    ERRORS=$((ERRORS + 1))
    warn_cli_error codex "$CODEX_RC" "$openaiModel" "models.openai" "$CODEX_OUT"
  else
    append_cli_verdict codex "$CODEX_OUT" ""
  fi
fi
if command -v gemini >/dev/null 2>&1; then
  GEMINI_OUT="$( build_review_prompt | vf_run_timeout 90 gemini $GEMINI_MFLAG 2>&1 )"
  GEMINI_RC=$?
  if (( GEMINI_RC == 124 )); then
    echo "consensus-run: gemini timed out after 90s (model: ${geminiModel:-<CLI default>})" >&2
    append_cli_verdict gemini '{"verdict":"REJECTED","criticalIssues":0}' "cli_timeout"
  elif (( GEMINI_RC != 0 )); then
    ERRORS=$((ERRORS + 1))
    warn_cli_error gemini "$GEMINI_RC" "$geminiModel" "models.gemini" "$GEMINI_OUT"
  else
    append_cli_verdict gemini "$GEMINI_OUT" ""
  fi
fi

# A reviewer counts only if it produced a verdict line. If every present CLI
# errored, there is no panel → fail loudly (the per-CLI warnings above name
# the fix) instead of writing a meaningless verdict.
if [[ -f "$LOG" ]]; then
  LINES="$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"
else
  LINES=0
fi
[[ "$LINES" =~ ^[0-9]+$ ]] || LINES=0
if (( LINES == 0 )); then
  echo "consensus-run: no reviewer produced a verdict ($ERRORS CLI error(s)). Fix the model id(s) in" >&2
  echo "  vibeflow.config.json (models.openai / models.gemini), or set them to \"default\" to defer to" >&2
  echo "  each CLI's own configured model. Or run /vibeflow:consensus-orchestrator (adds claude-reviewer)." >&2
  rm -f "$CONS_DIR/$SESSION_ID.current-round.txt" "$CONS_DIR/$SESSION_ID.primary.txt"
  exit 3
fi

# --- Step 3: finalize the verdict (no quorum stall) ----------------------
# The aggregator's --finalize mode computes verdict.json from whatever
# reviewer lines exist for this session+round, bypassing the SubagentStop
# stdin ingest + the 600s quorum wait (we KNOW the panel is complete —
# it's exactly the CLIs we just ran). It still writes history.jsonl,
# reviewer-memory, and evaluates the auto-revert watch — identical to the
# interactive path's finalization.
AGG_ERR="$(bash "$SCRIPT_DIR/consensus-aggregator.sh" --finalize "$SESSION_ID" "$ROUND" 2>&1 >/dev/null)" || true

VERDICT_FILE="$CONS_DIR/$SESSION_ID.verdict.json"
if [[ ! -f "$VERDICT_FILE" ]]; then
  echo "consensus-run: aggregator did not produce a verdict.json (session=$SESSION_ID)" >&2
  echo "consensus-run: reviewer log: $LOG ($(wc -l < "$LOG" 2>/dev/null | tr -d ' ') line(s))" >&2
  [[ -n "$AGG_ERR" ]] && echo "consensus-run: aggregator stderr: $AGG_ERR" >&2
  exit 1
fi

STATUS="$(jq -r '.status // "NEEDS_REVISION"' "$VERDICT_FILE" 2>/dev/null || echo NEEDS_REVISION)"
AGREEMENT="$(jq -r '.agreement // 0' "$VERDICT_FILE" 2>/dev/null || echo 0)"
CRITICAL="$(jq -r '.criticalTotal // 0' "$VERDICT_FILE" 2>/dev/null || echo 0)"

# --- Step 4: drain the consensus-gate marker so work can continue --------
# Load-bearing: consensus-gate.sh blocks every Bash/Write/Edit while
# consensus-needed.json is present. The interactive orchestrator drains it
# in Step 3c.1; the headless runner must do the same.
rm -f "$STATE_DIR/consensus-needed.json" "$STATE_DIR/review-pending.json" 2>/dev/null || true

# Round marker + primary sidecar were consumed by --finalize (history row
# is already written); drop them so a re-run starts clean.
rm -f "$CONS_DIR/$SESSION_ID.current-round.txt" "$CONS_DIR/$SESSION_ID.primary.txt" 2>/dev/null || true

# Emit a compact machine-readable summary the caller (phase-runner) parses.
jq -n -c \
  --arg session "$SESSION_ID" \
  --arg status "$STATUS" \
  --arg verdictFile "$VERDICT_FILE" \
  --argjson agreement "$AGREEMENT" \
  --argjson critical "$CRITICAL" \
  --argjson reviewers "$LINES" \
  --arg primary "$PRIMARY" \
  '{sessionId:$session, status:$status, agreement:$agreement, criticalTotal:$critical, reviewers:$reviewers, primaryArtifact:$primary, verdictFile:$verdictFile}'
exit 0
