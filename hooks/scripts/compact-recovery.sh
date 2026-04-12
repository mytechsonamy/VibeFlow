#!/bin/bash
# VibeFlow Compact Recovery Hook (SessionStart / compact).
#
# Fires after Claude Code compacts the conversation. We re-inject a snapshot
# of the live SDLC state so the model isn't left reasoning from a stale
# summary. The snapshot is assembled from .vibeflow/state.db at hook time
# (not read from a cached file) so it always reflects the latest writes that
# happened before compaction — fixes Bug #11.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

CONFIG="$(vf_config_path)"
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

DOMAIN="$(vf_config_get ".domain" || echo "general")"
MODE="$(vf_mode)"
PHASE="$(vf_current_phase)"
CONSENSUS="$(vf_last_consensus_status 2>/dev/null || echo "")"
SATISFIED="$(vf_satisfied_criteria)"

SATISFIED_LIST="(none)"
if vf_have_jq; then
  COUNT="$(echo "$SATISFIED" | jq 'length' 2>/dev/null || echo 0)"
  if [[ "$COUNT" != "0" ]]; then
    SATISFIED_LIST="$(echo "$SATISFIED" | jq -r '. | join(", ")')"
  fi
fi

# Also surface any pending review marker — after compaction, it's easy to
# forget that a multi-AI review is in flight.
REVIEW_NOTE=""
REVIEW_MARKER="$(vf_state_dir)/review-pending.json"
if [[ -f "$REVIEW_MARKER" ]] && vf_have_jq; then
  REVIEW_LINES="$(jq -r '.changedLines // 0' "$REVIEW_MARKER" 2>/dev/null || echo 0)"
  REVIEW_SHA="$(jq -r '.commitSha // "?"' "$REVIEW_MARKER" 2>/dev/null || echo "?")"
  REVIEW_NOTE=" Pending AI review: ${REVIEW_LINES} lines @ ${REVIEW_SHA:0:8}."
fi

cat <<EOF
VibeFlow context restored after compact.
 phase=$PHASE, mode=$MODE, domain=$DOMAIN${CONSENSUS:+, last_consensus=$CONSENSUS}
 satisfied_criteria: $SATISFIED_LIST
${REVIEW_NOTE:+$REVIEW_NOTE}
Run /vibeflow:status for full state.
EOF
exit 0
