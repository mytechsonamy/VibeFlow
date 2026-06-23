#!/bin/bash
# VibeFlow work-stream resolver (Sprint 60) — READ-ONLY.
#
# Prints the resolved work-stream id, the lifecycle.json path, and the
# current git branch as one JSON object. Skills (onboard / phase-runner /
# brownfield-intake / streams) call this once to learn which projectId to
# pass to the sdlc-engine MCP and which lifecycle file to read/write.
#
# It only READS state (config + git branch) — it never writes, advances, or
# moves past the consensus requirement, so consensus-gate allowlists it
# (like ui-styling-check.sh / loop-audit.sh). Never crashes the caller:
# every field degrades to "" on failure.
#
# Usage:  bash hooks/scripts/stream-id.sh
# Output: {"streamId":"acme__feature-auth","lifecycle":"<abs>","branch":"feature/auth"}

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

sid="$(vf_stream_id 2>/dev/null || echo "")"
lc="$(vf_lifecycle_path 2>/dev/null || echo "")"
branch=""
if command -v git >/dev/null 2>&1; then
  branch="$(git -C "$(vf_cwd)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi

if vf_have_jq; then
  jq -nc --arg s "$sid" --arg l "$lc" --arg b "$branch" \
    '{streamId:$s, lifecycle:$l, branch:$b}'
else
  printf '{"streamId":"%s","lifecycle":"%s","branch":"%s"}\n' "$sid" "$lc" "$branch"
fi
