#!/bin/bash
# VibeFlow phase-write-guard (PreToolUse/Write|Edit).
#
# Blocks file writes that violate the current SDLC phase's path policy.
# Defense-in-depth partner to commit-guard.sh: where commit-guard stops
# bad commits at `git commit` time, this stops bad writes at Write/Edit
# time so a skill can't silently scaffold source code during REQUIREMENTS.
#
# Policy lives in hooks/scripts/phase-policy.json. Each phase has an
# `allow` glob list (exit 0 silent) and a `warn` glob list (exit 0 plus
# stderr message). Anything not matching either list is denied with
# exit 2.
#
# Contract:
#   stdin  = JSON  {"tool_input": {"file_path": "..."}}
#   stdout = JSON  {"continue": true}   (when allowed)
#   stderr = human-readable message     (when blocked or warned)
#   exit   = 0  allow (silent or warned)
#          = 2  block
#
# Escape hatches:
#   VF_ALLOW_PHASE_WRITE=1   per-call dev override; always allows.
#   No policy file present   fail-safe allow (never brick an install).
#   Empty file_path          graceful allow (e.g. MultiEdit variants).
#   python3 not on PATH      fail-safe allow (matcher needs python).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Always drain stdin so the caller never blocks on a closed pipe.
INPUT="$(cat || true)"

# Escape hatch: per-call dev override.
if [[ "${VF_ALLOW_PHASE_WRITE:-}" == "1" ]]; then
  echo '{"continue":true}'
  exit 0
fi

# Extract target file_path from the PreToolUse JSON envelope.
FILE=""
if vf_have_jq && [[ -n "$INPUT" ]]; then
  FILE="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")"
fi

# Graceful: nothing to check (MultiEdit, tool-use without file_path).
if [[ -z "$FILE" ]]; then
  echo '{"continue":true}'
  exit 0
fi

# Fail-safe: missing policy file → allow. Framework never bricks a repo.
POLICY="$(vf_policy_path)"
if [[ ! -f "$POLICY" ]]; then
  echo '{"continue":true}'
  exit 0
fi

PHASE="$(vf_current_phase)"
REL="$(vf_relpath "$FILE")"

DECISION="$(vf_phase_decision "$PHASE" "$REL" "$POLICY" 2>/dev/null || echo "allow")"

case "$DECISION" in
  allow)
    echo '{"continue":true}'
    exit 0
    ;;
  warn)
    echo "VibeFlow phase-write-guard: $PHASE phase discourages writes to $REL (warn-only). Prefer confined edits; continue if you know what you're doing." >&2
    echo '{"continue":true}'
    exit 0
    ;;
  block|*)
    echo "VibeFlow phase-write-guard: $PHASE phase does not permit writes to $REL. Run /vibeflow:advance to progress the SDLC, or set VF_ALLOW_PHASE_WRITE=1 to bypass this single call." >&2
    exit 2
    ;;
esac
