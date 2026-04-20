#!/bin/bash
# VibeFlow SDLC Context Loader (SessionStart / startup|resume).
#
# Reads .vibeflow/state/<project>/project.json (or vibeflow.config.json
# fallback) for authoritative SDLC state and prints a concise context
# summary. Claude Code injects stdout into the session as a system
# note, so this runs once on session start and stays out of tool-call
# budget.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

CONFIG="$(vf_config_path)"
if [[ ! -f "$CONFIG" ]]; then
  echo "VibeFlow: No vibeflow.config.json found. Use /vibeflow:init to initialize."
  exit 0
fi

DOMAIN="$(vf_config_get ".domain" || echo "general")"
PHASE="$(vf_current_phase)"
CONSENSUS="$(vf_last_consensus_status 2>/dev/null || echo "")"
SATISFIED="$(vf_satisfied_criteria)"

# Degraded-state detection: if neither project.json nor state.db is
# available, phase comes from vibeflow.config.json.currentPhase which
# can be stale. Surface the degradation so the model knows.
DEGRADED_NOTE=""
if ! vf_project_json >/dev/null 2>&1; then
  STATE_DB="$(vf_state_db)"
  if [[ ! -f "$STATE_DB" ]]; then
    DEGRADED_NOTE=" (degraded: no project.json; phase read from config)"
  elif ! vf_have_sqlite3; then
    DEGRADED_NOTE=" (degraded: sqlite3 unavailable; phase read from config)"
  fi
fi

SATISFIED_COUNT=0
if vf_have_jq; then
  SATISFIED_COUNT="$(echo "$SATISFIED" | jq 'length' 2>/dev/null || echo 0)"
fi

LINE="VibeFlow active: domain=$DOMAIN, phase=$PHASE"
if [[ -n "$CONSENSUS" ]]; then
  LINE+=", last_consensus=$CONSENSUS"
fi
LINE+=", satisfied_criteria=$SATISFIED_COUNT$DEGRADED_NOTE"
echo "$LINE"
echo "Use /vibeflow:status for full state, /vibeflow:advance to move phase."
exit 0
