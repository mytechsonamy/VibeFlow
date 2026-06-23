#!/bin/bash
# VibeFlow Streams Audit reader (Sprint 60).
#
# Read-only. Lists every work-stream that has local state under
# .vibeflow/state/<streamId>/ and emits one compact JSON summary on stdout
# for the /vibeflow:streams dashboard + the /vibeflow:flow-status one-liner.
#
# A "stream" is any `.vibeflow/state/<dir>/` that contains a `project.json`
# (so framework dirs like auto-apply/ consensus/ patches/ are skipped). For
# each it reads the engine rollup (currentPhase/revision/updatedAt) and, if
# present, that stream's lifecycle.json (cycle id/title/status/branch).
#
# Everything is guarded — an absent/parse-failing file degrades to empty so
# a fresh project never errors. Single-machine scope: it sees the streams
# whose state lives in THIS checkout/worktree (see docs/TEAM-WORK.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

EMPTY='{"streamsEnabled":false,"currentStreamId":"","owner":"","streams":[],"conflicts":[]}'

if ! vf_have_jq; then
  echo "$EMPTY"
  exit 0
fi

CWD="$(vf_cwd)"
STATE_DIR="$CWD/.vibeflow/state"
ENABLED="$(vf_config_get '.streams.enabled' 2>/dev/null || echo "false")"
[[ "$ENABLED" == "true" ]] || ENABLED="false"
CURRENT="$(vf_stream_id 2>/dev/null || echo "")"
OWNER=""
if command -v git >/dev/null 2>&1; then
  OWNER="$(git -C "$CWD" config user.name 2>/dev/null || echo "")"
fi

STREAMS="[]"
if [[ -d "$STATE_DIR" ]]; then
  for pjson in "$STATE_DIR"/*/project.json; do
    [[ -f "$pjson" ]] || continue
    sdir="$(dirname "$pjson")"
    sid="$(basename "$sdir")"

    phase="$(jq -r '.currentPhase // ""' "$pjson" 2>/dev/null || echo "")"
    revision="$(jq -r '.revision // 0' "$pjson" 2>/dev/null || echo "0")"
    updated="$(jq -r '.updatedAt // ""' "$pjson" 2>/dev/null || echo "")"

    # That stream's lifecycle.json (co-located when streams on). Fall back to
    # the legacy single state/lifecycle.json for the bare-project stream.
    lc="$sdir/lifecycle.json"
    [[ -f "$lc" ]] || lc="$STATE_DIR/lifecycle.json"
    cid=""; ctitle=""; cstatus=""; cbranch=""
    if [[ -f "$lc" ]]; then
      cid="$(jq -r '.currentCycle.id // ""' "$lc" 2>/dev/null || echo "")"
      ctitle="$(jq -r '.currentCycle.title // ""' "$lc" 2>/dev/null || echo "")"
      cstatus="$(jq -r '.currentCycle.status // ""' "$lc" 2>/dev/null || echo "")"
      cbranch="$(jq -r '.currentCycle.branch // ""' "$lc" 2>/dev/null || echo "")"
    fi

    is_current="false"
    [[ -n "$CURRENT" && "$sid" == "$CURRENT" ]] && is_current="true"

    row="$(jq -nc \
      --arg sid "$sid" --arg phase "$phase" --argjson rev "${revision:-0}" \
      --arg updated "$updated" --arg cid "$cid" --arg ctitle "$ctitle" \
      --arg cstatus "$cstatus" --arg cbranch "$cbranch" --argjson cur "$is_current" \
      '{streamId:$sid, phase:$phase, revision:$rev, updatedAt:$updated,
        cycleId:$cid, cycleTitle:$ctitle, cycleStatus:$cstatus,
        branch:$cbranch, isCurrent:$cur}' 2>/dev/null || echo "")"
    [[ -n "$row" ]] && STREAMS="$(echo "$STREAMS" | jq -c --argjson r "$row" '. + [$r]' 2>/dev/null || echo "$STREAMS")"
  done
fi

# Conflicts: two distinct streams whose recorded branch is the same (only
# possible via VIBEFLOW_STREAM overrides / idStrategy:fixed — branch-derived
# ids can't collide). Surfaced so the operator notices shared-branch state.
CONFLICTS="$(echo "$STREAMS" | jq -c '
  [ .[] | select(.branch != "") ]
  | group_by(.branch)
  | map(select(length > 1) | {branch:.[0].branch, streamIds:[.[].streamId]})
' 2>/dev/null || echo "[]")"
[[ -n "$CONFLICTS" ]] || CONFLICTS="[]"

jq -nc \
  --argjson en "$([[ "$ENABLED" == "true" ]] && echo true || echo false)" \
  --arg cur "$CURRENT" --arg owner "$OWNER" \
  --argjson streams "$STREAMS" --argjson conflicts "$CONFLICTS" \
  '{streamsEnabled:$en, currentStreamId:$cur, owner:$owner,
    streams:$streams, conflicts:$conflicts}'
