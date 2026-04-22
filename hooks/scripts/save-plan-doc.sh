#!/bin/bash
# VibeFlow save-plan-doc hook (PostToolUse / ExitPlanMode).
#
# Persists the approved plan markdown into the project's docs/
# folder so sprint plans survive beyond Claude Code's ephemeral
# ~/.claude/plans/<slug>.md scratch location. Closes the process
# gap where docs/SPRINT-*.md stopped at SPRINT-13.md despite
# Sprints 14-18 having shipped.
#
# Output path resolution:
#   - Title matches /^#\s*Sprint\s+(\d+)/   → <cwd>/docs/SPRINT-<N>.md
#   - Otherwise                              → <cwd>/docs/plans/<slug>-<YYYYMMDD>.md
#
# Fail-safes (every one exits 0 so ExitPlanMode never blocks):
#   - missing jq                 → silent exit
#   - non-VibeFlow project        → silent exit (guard: vibeflow.config.json presence)
#   - missing plans dir           → silent exit
#   - VF_SKIP_PLAN_SAVE=1         → env bypass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat || true)"

if ! vf_have_jq; then
  exit 0
fi

if [[ "${VF_SKIP_PLAN_SAVE:-}" == "1" ]]; then
  exit 0
fi

# Empty or unparseable stdin → nothing to do.
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  exit 0
fi

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
if [[ -z "$CWD" ]] || [[ ! -d "$CWD" ]]; then
  exit 0
fi

# Guard: only activate inside VibeFlow-aware projects. Same pattern
# consensus-gate.sh uses to avoid polluting unrelated Claude Code
# sessions.
if [[ ! -f "$CWD/vibeflow.config.json" ]]; then
  exit 0
fi

PLANS_DIR="$HOME/.claude/plans"
if [[ ! -d "$PLANS_DIR" ]]; then
  exit 0
fi

# Newest .md in plans dir = the plan that was just approved.
# `ls -t` sorts by mtime descending; head -1 picks the freshest.
PLAN_FILE="$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)"
if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
  exit 0
fi

# First heading line (# …) — used for sprint-number detection and
# fallback slug generation.
FIRST_HEADING="$(grep -m1 '^#' "$PLAN_FILE" 2>/dev/null || echo "")"

# Sprint number extraction: /^#\s*Sprint\s+(\d+)/i
SPRINT_NUM=""
if [[ "$FIRST_HEADING" =~ ^#[[:space:]]*[Ss]print[[:space:]]+([0-9]+) ]]; then
  SPRINT_NUM="${BASH_REMATCH[1]}"
fi

mkdir -p "$CWD/docs" "$CWD/docs/plans" 2>/dev/null || true

OUT_PATH=""
if [[ -n "$SPRINT_NUM" ]]; then
  OUT_PATH="$CWD/docs/SPRINT-${SPRINT_NUM}.md"
else
  # Fallback: sanitise the first heading into a slug.
  SLUG="$(printf '%s' "$FIRST_HEADING" \
    | sed -E 's/^#[[:space:]]*//; s/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | tr '[:upper:]' '[:lower:]' \
    | cut -c1-60)"
  [[ -z "$SLUG" ]] && SLUG="plan"
  DATESTAMP="$(date -u +%Y%m%d)"
  OUT_PATH="$CWD/docs/plans/${SLUG}-${DATESTAMP}.md"
fi

# Copy the plan. cp -f preserves content byte-for-byte and
# overwrites an existing file (intentional — re-approving a plan
# on the same sprint should update the doc, not pile up variants).
if cp -f "$PLAN_FILE" "$OUT_PATH" 2>/dev/null; then
  # Advisory on stderr — Claude Code surfaces hook stderr to the
  # model. Keep it brief.
  REL_OUT="${OUT_PATH#$CWD/}"
  echo "VibeFlow: plan saved to $REL_OUT" >&2
else
  echo "VibeFlow: plan save failed (cp $PLAN_FILE → $OUT_PATH). Save manually." >&2
fi

exit 0
