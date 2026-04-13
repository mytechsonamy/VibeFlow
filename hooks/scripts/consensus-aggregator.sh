#!/bin/bash
# VibeFlow Consensus Aggregator Hook (SubagentStop / *).
#
# Runs whenever a subagent finishes. We record the verdict in
# .vibeflow/state/consensus/<session>.jsonl — one line per reviewer — and,
# once the expected reviewer count is reached (3 for team, 1 for solo),
# compute an aggregate status + agreement ratio and write verdict.json.
#
# The aggregator is intentionally a narrow parser: it scans the subagent's
# output text for "APPROVED", "NEEDS_REVISION", "REJECTED" keywords and a
# "critical issues: N" pattern. Richer structured verdicts will come from
# the consensus-orchestrator skill in Sprint 2.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat)"
if ! vf_have_jq; then
  echo '{"continue": true}'
  exit 0
fi

STATE_DIR="$(vf_state_dir)"
CONS_DIR="$STATE_DIR/consensus"
mkdir -p "$CONS_DIR"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "default"')"
SUBAGENT="$(echo "$INPUT" | jq -r '.subagent_type // .tool_name // "unknown"')"
# Claude Code stopped-subagent payloads vary; try the common shapes.
OUTPUT="$(echo "$INPUT" | jq -r '.tool_response.content[0].text // .result // .output // ""')"

# Verdict extraction. Order matters — REJECTED outranks NEEDS_REVISION,
# which outranks APPROVED. If none match, record UNKNOWN so the reviewer
# still counts toward quorum but does not pull the aggregate toward pass.
VERDICT="UNKNOWN"
if [[ "$OUTPUT" =~ REJECTED ]]; then
  VERDICT="REJECTED"
elif [[ "$OUTPUT" =~ NEEDS_REVISION|NEEDS[[:space:]]REVISION ]]; then
  VERDICT="NEEDS_REVISION"
elif [[ "$OUTPUT" =~ APPROVED ]]; then
  VERDICT="APPROVED"
fi

CRITICAL=0
if [[ "$OUTPUT" =~ critical[[:space:]]+issues[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  CRITICAL="${BASH_REMATCH[1]}"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REVIEW_LOG="$CONS_DIR/$SESSION_ID.jsonl"
jq -n -c \
  --arg ts "$TS" \
  --arg reviewer "$SUBAGENT" \
  --arg verdict "$VERDICT" \
  --argjson critical "$CRITICAL" \
  '{recordedAt:$ts, reviewer:$reviewer, verdict:$verdict, criticalIssues:$critical}' \
  >> "$REVIEW_LOG"

# Expected reviewer count comes from mode: team requires 3, solo requires 1.
MODE="$(vf_mode)"
EXPECTED=1
if [[ "$MODE" == "team" ]]; then
  EXPECTED=3
fi

COUNT="$(wc -l < "$REVIEW_LOG" | tr -d ' ')"

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
AGG="$(jq -s '
  {
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
echo "$AGG" \
  | jq --arg ts "$TS" \
       --arg session "$SESSION_ID" \
       --argjson expected "$EXPECTED" \
       --argjson count "$COUNT" \
       --argjson timed_out "$TIMED_OUT" \
       '. + {
          finalizedAt: $ts,
          sessionId: $session,
          expectedReviewers: $expected,
          receivedReviewers: $count,
          timeout: $timed_out,
          status: (if $timed_out and .status == "APPROVED" then "NEEDS_REVISION" else .status end)
        }' > "$VERDICT_FILE"

# Roll the session log forward: archive it so a subsequent run in the same
# session starts fresh rather than stacking on an already-finalized batch.
mv "$REVIEW_LOG" "$CONS_DIR/$SESSION_ID.$(date -u +%s).archived.jsonl"

echo '{"continue": true}'
exit 0
