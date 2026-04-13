#!/bin/bash
# VibeFlow AI Review Trigger (PostToolUse / Bash / git commit, async).
#
# Fires after a successful commit. When the diff is large enough to warrant a
# multi-AI review (threshold: 50 changed lines), writes a marker at
# .vibeflow/state/review-pending.json so the next consensus-orchestrator run
# picks it up. In solo mode, reviews are disabled by policy and the marker is
# never written.
#
# async=true in hooks.json — this runs after the tool call returns, so output
# is not injected into the session. All side effects go through the state dir.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Drain stdin so the caller never blocks on a closed pipe.
cat >/dev/null || true

if [[ ! -f "$(vf_config_path)" ]]; then
  exit 0
fi

MODE="$(vf_mode)"
if [[ "$MODE" == "solo" ]]; then
  # Solo mode: single-AI, no cross-model consensus.
  exit 0
fi

# Count changed lines in the most recent commit (HEAD). --numstat gives
# added<TAB>deleted<TAB>path; sum columns 1 and 2 over all rows. Binary files
# show '-' and are excluded from the sum.
CHANGED_LINES=0
if command -v git >/dev/null 2>&1 && git -C "$(vf_cwd)" rev-parse --git-dir >/dev/null 2>&1; then
  CHANGED_LINES="$(git -C "$(vf_cwd)" show --numstat --format= HEAD 2>/dev/null \
    | awk 'BEGIN{s=0} $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { s += $1 + $2 } END{print s}')"
fi
CHANGED_LINES="${CHANGED_LINES:-0}"

THRESHOLD=50
if (( CHANGED_LINES < THRESHOLD )); then
  exit 0
fi

STATE_DIR="$(vf_state_dir)"
MARKER="$STATE_DIR/review-pending.json"
COMMIT_SHA=""
if command -v git >/dev/null 2>&1; then
  COMMIT_SHA="$(git -C "$(vf_cwd)" rev-parse HEAD 2>/dev/null || echo "")"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PHASE="$(vf_current_phase)"

# Rate limit: max 1 review marker per 5 minutes. If an existing marker
# was written less than 300 seconds ago, leave it alone — the
# consensus-orchestrator picks up at most one batch at a time and
# rewriting would reset its queue position. A commit that's rate-limited
# still ran the guard, it just doesn't kick a fresh review.
RATE_LIMIT_SECONDS=300
if [[ -f "$MARKER" ]] && vf_have_jq; then
  EXISTING_TS="$(jq -r '.requestedAt // empty' "$MARKER" 2>/dev/null || echo "")"
  if [[ -n "$EXISTING_TS" ]] && command -v python3 >/dev/null 2>&1; then
    NOW_EPOCH="$(date -u +%s)"
    EXISTING_EPOCH="$(python3 -c "import datetime;print(int(datetime.datetime.strptime('$EXISTING_TS','%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()))" 2>/dev/null || echo "")"
    if [[ -n "$EXISTING_EPOCH" ]] && (( NOW_EPOCH - EXISTING_EPOCH < RATE_LIMIT_SECONDS )); then
      exit 0
    fi
  fi
fi

# Single-writer: last commit wins. Overwrite is safer than append for a
# pending-work marker — consensus-orchestrator picks up at most one batch.
if vf_have_jq; then
  jq -n \
    --arg ts "$TS" \
    --arg phase "$PHASE" \
    --arg sha "$COMMIT_SHA" \
    --argjson lines "$CHANGED_LINES" \
    --argjson threshold "$THRESHOLD" \
    '{requestedAt:$ts, phase:$phase, commitSha:$sha, changedLines:$lines, threshold:$threshold, status:"pending"}' \
    > "$MARKER"
else
  printf '{"requestedAt":"%s","phase":"%s","commitSha":"%s","changedLines":%s,"threshold":%s,"status":"pending"}\n' \
    "$TS" "$PHASE" "$COMMIT_SHA" "$CHANGED_LINES" "$THRESHOLD" > "$MARKER"
fi

exit 0
