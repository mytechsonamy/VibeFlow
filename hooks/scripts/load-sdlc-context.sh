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

# Sprint 15-D: review-pending marker drain. trigger-ai-review writes
# .vibeflow/state/review-pending.json after large commits, but
# nothing reads it on its own. Surface the marker here as a strong
# SessionStart instruction so the orchestrator actually runs — the
# post-commit half of the MyVibe auto-review promise.
MARKER="$(vf_state_dir)/review-pending.json"
if [[ -f "$MARKER" ]] && vf_have_jq; then
  REQ_AT="$(jq -r '.requestedAt // empty' "$MARKER" 2>/dev/null || echo "")"
  AGE_OK=true
  if [[ -n "$REQ_AT" ]] && command -v python3 >/dev/null 2>&1; then
    AGE_OK="$(python3 -c "
import datetime, sys
try:
    ts = datetime.datetime.strptime('$REQ_AT', '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
    hours = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds() / 3600
    print('true' if hours < 24 else 'false')
except Exception:
    print('false')
" 2>/dev/null || echo "true")"
  fi
  if [[ "$AGE_OK" == "true" ]]; then
    SHA="$(jq -r '.commitSha // "?"' "$MARKER" 2>/dev/null || echo "?")"
    LINES="$(jq -r '.changedLines // 0' "$MARKER" 2>/dev/null || echo 0)"
    echo "VibeFlow: unreviewed commit pending (sha=${SHA:0:8}, +${LINES} lines)."
    echo "ACTION REQUIRED: run /vibeflow:consensus-orchestrator to drain the review queue."
  fi
fi

# Sprint 15-D: escape hatch advisory. If auto-consensus is globally
# disabled for this session, announce it explicitly so the model
# isn't surprised when no consensus fires after a skill run.
if [[ "${VF_SKIP_AUTO_CONSENSUS:-}" == "1" ]]; then
  echo "VibeFlow: auto-consensus disabled via VF_SKIP_AUTO_CONSENSUS=1 for this session."
fi

# Sprint 17-C: surface the most recent phase_advanced event that
# carries a humanOverrideNote (advance ran under HUMAN_APPROVAL_REQUIRED).
# Missing jq / missing events dir / no override just falls through
# silently — the advisory is purely informational.
if vf_have_jq; then
  EVENTS_DIR=""
  PDIR="$(vf_state_project_dir 2>/dev/null || true)"
  if [[ -n "$PDIR" ]] && [[ -d "$PDIR/events" ]]; then
    EVENTS_DIR="$PDIR/events"
  fi
  if [[ -n "$EVENTS_DIR" ]]; then
    LATEST_OVERRIDE=""
    # Walk phase_advanced event files newest-first.
    for f in $(ls -1t "$EVENTS_DIR"/*phase_advanced*.json 2>/dev/null); do
      if jq -e '.payload.humanOverrideNote // empty' "$f" >/dev/null 2>&1; then
        LATEST_OVERRIDE="$f"
        break
      fi
    done
    if [[ -n "$LATEST_OVERRIDE" ]] && [[ -f "$LATEST_OVERRIDE" ]]; then
      OV_AT="$(jq -r '.recordedAt // "?"' "$LATEST_OVERRIDE" 2>/dev/null || echo "?")"
      OV_FROM="$(jq -r '.payload.from // "?"' "$LATEST_OVERRIDE" 2>/dev/null || echo "?")"
      OV_TO="$(jq -r '.payload.to // "?"' "$LATEST_OVERRIDE" 2>/dev/null || echo "?")"
      OV_NOTE="$(jq -r '.payload.humanOverrideNote // ""' "$LATEST_OVERRIDE" 2>/dev/null || echo "")"
      OV_NOTE="${OV_NOTE:0:120}"
      echo "VibeFlow: last phase advance (${OV_FROM} → ${OV_TO} at ${OV_AT:0:10}) ran under HUMAN_APPROVAL_REQUIRED."
      if [[ -n "$OV_NOTE" ]]; then
        echo "  Override note: $OV_NOTE"
      fi
    fi
  fi
fi

echo "Use /vibeflow:status for full state, /vibeflow:advance to move phase."
exit 0
