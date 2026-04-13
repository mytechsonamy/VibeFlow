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

# Integrity check: fires after compact so the model knows when state is
# approximate. Walks through four checks, collecting failure reasons:
#   1. state.db exists and sqlite3 can open it
#   2. satisfied_criteria parses as JSON
#   3. config.currentPhase matches state.db.current_phase (when both present)
#   4. jq is available to parse the satisfied_criteria list
# A failure on any check sets INTEGRITY_DEGRADED and records the reason.
INTEGRITY_DEGRADED=false
INTEGRITY_REASONS=""
append_reason() {
  if [[ -z "$INTEGRITY_REASONS" ]]; then
    INTEGRITY_REASONS="$1"
  else
    INTEGRITY_REASONS="$INTEGRITY_REASONS; $1"
  fi
}

STATE_DB="$(vf_state_db)"
if [[ ! -f "$STATE_DB" ]]; then
  INTEGRITY_DEGRADED=true
  append_reason "state.db missing"
elif vf_have_sqlite3; then
  if ! sqlite3 "$STATE_DB" "SELECT 1;" >/dev/null 2>&1; then
    INTEGRITY_DEGRADED=true
    append_reason "state.db unreadable"
  fi
else
  INTEGRITY_DEGRADED=true
  append_reason "sqlite3 not installed; reading from config only"
fi

SATISFIED_LIST="(none)"
if vf_have_jq; then
  if ! echo "$SATISFIED" | jq empty >/dev/null 2>&1; then
    INTEGRITY_DEGRADED=true
    append_reason "satisfied_criteria is not valid JSON"
  else
    COUNT="$(echo "$SATISFIED" | jq 'length' 2>/dev/null || echo 0)"
    if [[ "$COUNT" != "0" ]]; then
      SATISFIED_LIST="$(echo "$SATISFIED" | jq -r '. | join(", ")')"
    fi
  fi
else
  INTEGRITY_DEGRADED=true
  append_reason "jq not installed; satisfied_criteria parsing skipped"
fi

# Cross-check: config.currentPhase vs state.db.current_phase should agree.
# When they don't, state.db wins (it's authoritative) but we surface the
# disagreement so downstream tooling can re-sync.
CONFIG_PHASE="$(vf_config_get ".currentPhase" || echo "")"
if [[ -n "$CONFIG_PHASE" && "$CONFIG_PHASE" != "$PHASE" ]]; then
  INTEGRITY_DEGRADED=true
  append_reason "config.currentPhase=$CONFIG_PHASE disagrees with state.db=$PHASE"
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

INTEGRITY_NOTE=""
if [[ "$INTEGRITY_DEGRADED" == "true" ]]; then
  INTEGRITY_NOTE=$'\n state integrity degraded: '"$INTEGRITY_REASONS"$'\n run /vibeflow:status to re-hydrate from source.'
fi

cat <<EOF
VibeFlow context restored after compact.
 phase=$PHASE, mode=$MODE, domain=$DOMAIN${CONSENSUS:+, last_consensus=$CONSENSUS}
 satisfied_criteria: $SATISFIED_LIST
${REVIEW_NOTE:+$REVIEW_NOTE}${INTEGRITY_NOTE}
Run /vibeflow:status for full state.
EOF
exit 0
