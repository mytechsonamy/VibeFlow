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
#
# NOTE (S13-A): this script is scaffold-only in Sprint 13-A. It is not
# yet wired into hooks/hooks.json; the full implementation (glob
# matching, policy parsing) lands in Sprint 13-B, and hooks.json wiring
# in Sprint 13-C.

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

# In Sprint 13-A the guard is dead code — it drains stdin, honours the
# escape hatch, and always allows. Real logic arrives in Sprint 13-B.
echo '{"continue":true}'
exit 0
