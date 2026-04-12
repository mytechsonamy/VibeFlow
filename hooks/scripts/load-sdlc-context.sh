#!/bin/bash
# VibeFlow SDLC Context Loader (SessionStart / startup|resume).
#
# Queries .vibeflow/state.db for authoritative SDLC state and prints a concise
# context summary. Claude Code injects stdout into the session as a system
# note, so this runs once on session start and stays out of tool-call budget.

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
MODE="$(vf_mode)"
PHASE="$(vf_current_phase)"
CONSENSUS="$(vf_last_consensus_status 2>/dev/null || echo "")"
SATISFIED="$(vf_satisfied_criteria)"

SATISFIED_COUNT=0
if vf_have_jq; then
  SATISFIED_COUNT="$(echo "$SATISFIED" | jq 'length' 2>/dev/null || echo 0)"
fi

LINE="VibeFlow active: domain=$DOMAIN, mode=$MODE, phase=$PHASE"
if [[ -n "$CONSENSUS" ]]; then
  LINE+=", last_consensus=$CONSENSUS"
fi
LINE+=", satisfied_criteria=$SATISFIED_COUNT"
echo "$LINE"
echo "Use /vibeflow:status for full state, /vibeflow:advance to move phase."
exit 0
