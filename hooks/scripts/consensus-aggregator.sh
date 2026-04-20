#!/bin/bash
# VibeFlow Consensus Aggregator Hook (SubagentStop / *).
#
# Runs whenever a subagent finishes. We record the verdict in
# .vibeflow/state/consensus/<session>.jsonl — one line per reviewer — and,
# once the expected reviewer count is reached, compute an aggregate
# status + agreement ratio and write verdict.json.
#
# Expected reviewer count is driven by CLI availability, not by a
# solo/team mode switch (Sprint 14-A). claude-reviewer always
# participates; codex and gemini are added when their CLIs are on PATH.
# Sprint 14-B lets operators override the count via
# `consensus.quorum` in vibeflow.config.json when the detected set
# doesn't match the intended reviewer roster.
#
# The aggregator is intentionally a narrow parser: it scans the subagent's
# output text for "APPROVED", "NEEDS_REVISION", "REJECTED" keywords and a
# "critical issues: N" pattern. Richer structured verdicts come from the
# consensus-orchestrator skill's markdown output.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat)"
if ! vf_have_jq; then
  echo '{"continue": true}'
  exit 0
fi

# Malformed/empty stdin → fail-safe allow and exit. Never abort the
# calling tool call just because the SubagentStop payload couldn't be
# parsed.
if [[ -z "$INPUT" ]] || ! printf %s "$INPUT" | jq empty >/dev/null 2>&1; then
  echo '{"continue": true}'
  exit 0
fi

STATE_DIR="$(vf_state_dir)"
CONS_DIR="$STATE_DIR/consensus"
mkdir -p "$CONS_DIR"

SESSION_ID="$(printf %s "$INPUT" | jq -r '.session_id // "default"')"
SUBAGENT="$(printf %s "$INPUT" | jq -r '.subagent_type // .tool_name // ""')"
# Claude Code stopped-subagent payloads vary; try the common shapes.
OUTPUT="$(printf %s "$INPUT" | jq -r '.tool_response.content[0].text // .result // .output // ""')"

# Sprint 14-B: only record verdicts from reviewer-class subagents.
# Before this guard, the aggregator fired on every SubagentStop (Explore,
# test-analyst, codebase-explorer, …) and labelled every unparseable
# output as `reviewer=unknown` / `verdict=UNKNOWN`, polluting the verdict
# log and forcing premature REJECTED finalization. We now skip silently
# when the stopping subagent isn't one we expect to produce a review.
case "$SUBAGENT" in
  claude-reviewer|reviewer|*-reviewer|consensus-*)
    : # known reviewer-class agent; fall through
    ;;
  *)
    # Not a reviewer subagent (or name missing entirely). Don't log.
    echo '{"continue": true}'
    exit 0
    ;;
esac

# Verdict extraction. Order matters — REJECTED outranks NEEDS_REVISION,
# which outranks APPROVED. Prefer the structured JSON `verdict` field
# from claude-reviewer's output schema; fall back to plain-text keyword
# matching for subagents that emit free-form prose. If neither yields a
# recognisable verdict, skip the entry entirely rather than logging a
# synthetic UNKNOWN — a missing reviewer must not short-circuit the
# aggregate.
VERDICT=""
# `-Rs` reads arbitrary text as a raw string; `try (fromjson ...) catch
# empty` tolerates non-JSON output (e.g. reviewers that emit prose).
STRUCTURED="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .verdict) catch empty' 2>/dev/null || true)"
case "$STRUCTURED" in
  APPROVED|NEEDS_REVISION|REJECTED) VERDICT="$STRUCTURED" ;;
esac
if [[ -z "$VERDICT" ]]; then
  if [[ "$OUTPUT" =~ REJECTED ]]; then
    VERDICT="REJECTED"
  elif [[ "$OUTPUT" =~ NEEDS_REVISION|NEEDS[[:space:]]REVISION ]]; then
    VERDICT="NEEDS_REVISION"
  elif [[ "$OUTPUT" =~ APPROVED ]]; then
    VERDICT="APPROVED"
  fi
fi
if [[ -z "$VERDICT" ]]; then
  # Reviewer-class subagent stopped with no parseable verdict. Silently
  # skip — a subsequent reviewer or a timeout will still finalise the
  # session.
  echo '{"continue": true}'
  exit 0
fi

# Critical-issue count: prefer structured output (claude-reviewer emits
# criticalIssues as a JSON array; len = count). Fall back to free-text
# "critical issues: N" for reviewers that don't emit structured JSON.
CRITICAL=0
STRUCTURED_CRITICAL="$(echo "$OUTPUT" | jq -Rsr 'try (fromjson | .criticalIssues | length) catch empty' 2>/dev/null || true)"
if [[ "$STRUCTURED_CRITICAL" =~ ^[0-9]+$ ]]; then
  CRITICAL="$STRUCTURED_CRITICAL"
elif [[ "$OUTPUT" =~ critical[[:space:]]+issues[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  CRITICAL="${BASH_REMATCH[1]}"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REVIEW_LOG="$CONS_DIR/$SESSION_ID.jsonl"

# Sprint 17-A: round-aware. Orchestrator writes the current round number
# to `<sid>.current-round.txt` before each negotiation round. Default 1
# when the marker is missing — single-round sessions keep working.
CURRENT_ROUND=1
ROUND_MARKER="$CONS_DIR/$SESSION_ID.current-round.txt"
if [[ -f "$ROUND_MARKER" ]]; then
  MARKER_VAL="$(head -n 1 "$ROUND_MARKER" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$MARKER_VAL" =~ ^[0-9]+$ ]] && (( MARKER_VAL >= 1 )); then
    CURRENT_ROUND="$MARKER_VAL"
  fi
fi

jq -n -c \
  --arg ts "$TS" \
  --arg reviewer "$SUBAGENT" \
  --arg verdict "$VERDICT" \
  --argjson critical "$CRITICAL" \
  --argjson round "$CURRENT_ROUND" \
  '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical, round:$round}' \
  >> "$REVIEW_LOG"

# Expected reviewer count is driven by which CLIs are on PATH + any
# explicit override in vibeflow.config.json's `consensus.quorum`.
# Default roster: claude-reviewer (always), codex (if CLI), gemini
# (if CLI). Operators who know their reviewers are stalled or missing
# can force a lower quorum via the config override.
EXPECTED_DETECTED=1
if command -v codex >/dev/null 2>&1; then
  EXPECTED_DETECTED=$((EXPECTED_DETECTED + 1))
fi
if command -v gemini >/dev/null 2>&1; then
  EXPECTED_DETECTED=$((EXPECTED_DETECTED + 1))
fi
EXPECTED_OVERRIDE="$(vf_config_get ".consensus.quorum" 2>/dev/null || echo "")"
if [[ -n "$EXPECTED_OVERRIDE" ]] && [[ "$EXPECTED_OVERRIDE" =~ ^[0-9]+$ ]]; then
  EXPECTED="$EXPECTED_OVERRIDE"
else
  EXPECTED="$EXPECTED_DETECTED"
fi

COUNT="$(jq -s --argjson round "$CURRENT_ROUND" 'map(select((.round // 1) == $round)) | length' < "$REVIEW_LOG" 2>/dev/null || wc -l < "$REVIEW_LOG" | tr -d ' ')"

# Timeout: if the oldest review in the log is older than 600 seconds and
# quorum has not been reached, force-finalize the batch with a `timeout:
# true` flag. This keeps the aggregator from stalling forever when one
# of the 3 team reviewers never responds (rate-limited, crashed,
# network dropped, etc.). The aggregator still records the latest
# review before finalizing, so the final verdict reflects what DID
# arrive.
TIMEOUT_SECONDS=600
TIMED_OUT=false
if (( COUNT < EXPECTED )); then
  FIRST_TS="$(head -n 1 "$REVIEW_LOG" | jq -r '.recordedAt // empty' 2>/dev/null || echo "")"
  if [[ -n "$FIRST_TS" ]] && command -v python3 >/dev/null 2>&1; then
    NOW_EPOCH="$(date -u +%s)"
    FIRST_EPOCH="$(python3 -c "import datetime;print(int(datetime.datetime.strptime('$FIRST_TS','%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()))" 2>/dev/null || echo "")"
    if [[ -n "$FIRST_EPOCH" ]] && (( NOW_EPOCH - FIRST_EPOCH >= TIMEOUT_SECONDS )); then
      TIMED_OUT=true
    fi
  fi
  if [[ "$TIMED_OUT" != "true" ]]; then
    echo '{"continue": true}'
    exit 0
  fi
fi

# Quorum reached OR timeout fired — compute aggregate. Agreement = (#
# APPROVED) / total. Status uses CLAUDE.md thresholds: >=0.9 + 0
# critical → APPROVED, <0.5 or >=2 critical → REJECTED, else
# NEEDS_REVISION. When timed out, the `timeout: true` flag is added and
# the status is demoted from APPROVED to NEEDS_REVISION (a partial
# quorum cannot ship a clean APPROVED verdict — the missing reviewer
# could have objected).
# Sprint 17-A: aggregation is now per-round. Filter jsonl to lines whose
# `round` matches CURRENT_ROUND (default 1 for legacy single-round
# sessions). `total`, `approved`, `criticalTotal`, `agreement`, `status`
# are the CURRENT round's values — these stay top-level so existing
# consumers (tests, arbiter, phase-gate) keep working untouched. A new
# `rounds[]` array accumulates per-round snapshots across negotiation
# rounds; orchestrator reads it to decide whether to invoke round N+1.
AGG="$(jq -s --argjson round "$CURRENT_ROUND" '
  map(select((.round // 1) == $round))
  | {
      total: length,
      approved: (map(select(.verdict == "APPROVED")) | length),
      needsRevision: (map(select(.verdict == "NEEDS_REVISION")) | length),
      rejected: (map(select(.verdict == "REJECTED")) | length),
      unknown: (map(select(.verdict == "UNKNOWN")) | length),
      criticalTotal: (map(.criticalIssues) | add // 0)
    }
  | . + { agreement: (if .total > 0 then (.approved / .total) else 0 end) }
  | . + {
      status: (
        if .criticalTotal >= 2 then "REJECTED"
        elif .agreement < 0.5 then "REJECTED"
        elif .agreement >= 0.9 and .criticalTotal == 0 then "APPROVED"
        else "NEEDS_REVISION"
        end
      )
    }
' < "$REVIEW_LOG")"

VERDICT_FILE="$CONS_DIR/$SESSION_ID.verdict.json"

# Read existing rounds[] so we preserve history across negotiation rounds.
EXISTING_ROUNDS="[]"
if [[ -f "$VERDICT_FILE" ]]; then
  EXISTING_ROUNDS="$(jq -c '.rounds // []' "$VERDICT_FILE" 2>/dev/null || echo "[]")"
fi

# Compose verdict.json: top-level = current round's numbers (back-compat);
# add `round` + `finalRound` + `rounds[]` (each entry is a minimal
# per-round snapshot so the orchestrator can see agreement curve).
echo "$AGG" \
  | jq --arg ts "$TS" \
       --arg session "$SESSION_ID" \
       --argjson expected "$EXPECTED" \
       --argjson count "$COUNT" \
       --argjson timed_out "$TIMED_OUT" \
       --argjson round "$CURRENT_ROUND" \
       --argjson existingRounds "$EXISTING_ROUNDS" \
       '. + {
          round: $round,
          finalRound: $round,
          finalizedAt: $ts,
          sessionId: $session,
          expectedReviewers: $expected,
          receivedReviewers: $count,
          timeout: $timed_out,
          status: (if $timed_out and .status == "APPROVED" then "NEEDS_REVISION" else .status end)
        }
        | . as $current
        | . + {
            rounds: ($existingRounds + [{
              round: $round,
              agreement: $current.agreement,
              criticalTotal: $current.criticalTotal,
              status: $current.status,
              timeout: $timed_out,
              finalizedAt: $ts
            }])
          }' > "$VERDICT_FILE"

# Archive current round's log so the next round starts on an empty jsonl.
# Legacy name kept for single-round callers; new name includes round
# number for multi-round sessions so the audit trail is navigable.
if [[ "$CURRENT_ROUND" -eq 1 ]] && [[ ! -f "$ROUND_MARKER" ]]; then
  mv "$REVIEW_LOG" "$CONS_DIR/$SESSION_ID.$(date -u +%s).archived.jsonl"
else
  mv "$REVIEW_LOG" "$CONS_DIR/$SESSION_ID.r${CURRENT_ROUND}.archived.jsonl"
fi

echo '{"continue": true}'
exit 0
