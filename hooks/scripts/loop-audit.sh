#!/bin/bash
# VibeFlow Loop Audit reader (Sprint 25-A).
#
# Read-only. Consolidates the scattered autonomous-loop telemetry into one
# compact JSON summary on stdout, for the /vibeflow:flow-status "Autonomous
# Loop" section (Sprint 25-B). Reads (all guarded — every absent file
# degrades to zeros/empties so a fresh project never errors):
#   - .vibeflow/state/consensus/history.jsonl   (auto-apply/-revert/-held)
#   - .vibeflow/state/auto-apply/cooldown-*      (cooled-down keys)
#   - .vibeflow/state/auto-apply/watch.json      (armed watch)
#   - .vibeflow/reports/consensus-learning-report.md  (finding count)
#   - .vibeflow/reports/learning-apply-decisions.md   (recent decisions)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

EMPTY='{"autoApply":{"applied":0,"reverted":0,"held":0,"armedWatch":null,"cooldowns":[]},"perKey":[],"learning":{"reportExists":false,"findingCount":0},"recentDecisions":[],"phaseRunner":null,"crossProject":null}'

if ! vf_have_jq; then
  echo "$EMPTY"
  exit 0
fi

STATE_DIR="$(vf_state_dir)"
CWD="$(vf_cwd)"
HISTORY="$STATE_DIR/consensus/history.jsonl"
AA_DIR="$STATE_DIR/auto-apply"
REPORT="$CWD/.vibeflow/reports/consensus-learning-report.md"
DECISIONS="$CWD/.vibeflow/reports/learning-apply-decisions.md"

WINDOW="$(vf_config_get '.loopAudit.window' 2>/dev/null || echo 20)"
[[ "$WINDOW" =~ ^[0-9]+$ ]] || WINDOW=20

# Cooled-down keys: cooldown-<key> markers.
COOLDOWNS="[]"
if [[ -d "$AA_DIR" ]]; then
  COOLDOWNS="$(find "$AA_DIR" -maxdepth 1 -name 'cooldown-*' -type f 2>/dev/null \
    | sed 's@.*/cooldown-@@' | jq -R . | jq -s . 2>/dev/null || echo "[]")"
  [[ -n "$COOLDOWNS" ]] || COOLDOWNS="[]"
fi

# Armed (pending-evaluation) watch, if any.
ARMED="null"
if [[ -f "$AA_DIR/watch.json" ]]; then
  ARMED="$(jq -c '{keys:(.keys // [.key]), phase:(.phase // ""), primaryArtifact:(.primaryArtifact // "")}' \
    "$AA_DIR/watch.json" 2>/dev/null || echo "null")"
  [[ -n "$ARMED" ]] || ARMED="null"
fi

# Per-key counts + totals from the last WINDOW auto-* rows of history.jsonl.
PERKEY="[]"; APPLIED=0; REVERTED=0; HELD=0
if [[ -f "$HISTORY" ]]; then
  AUTO_JSON="$(jq -s --argjson w "$WINDOW" --argjson cd "$COOLDOWNS" '
    [ .[] | select(.type=="auto-apply" or .type=="auto-revert" or .type=="auto-apply-held") ]
    | (.[-($w):]) as $rows
    | {
        perKey: ($rows | group_by(.key) | map(
          { key: .[0].key,
            applied:  (map(select(.type=="auto-apply"))      | length),
            reverted: (map(select(.type=="auto-revert"))     | length),
            held:     (map(select(.type=="auto-apply-held")) | length) } as $o
          | $o + { revertRate: (if $o.applied > 0 then (($o.reverted / $o.applied) * 100 | round) / 100 else 0 end),
                   cooledDown: (($cd | index($o.key)) != null) })),
        applied:  ([$rows[] | select(.type=="auto-apply")]      | length),
        reverted: ([$rows[] | select(.type=="auto-revert")]     | length),
        held:     ([$rows[] | select(.type=="auto-apply-held")] | length)
      }' "$HISTORY" 2>/dev/null || echo '{}')"
  PERKEY="$(printf '%s' "$AUTO_JSON" | jq -c '.perKey // []' 2>/dev/null || echo "[]")"
  APPLIED="$(printf '%s' "$AUTO_JSON" | jq -r '.applied // 0' 2>/dev/null || echo 0)"
  REVERTED="$(printf '%s' "$AUTO_JSON" | jq -r '.reverted // 0' 2>/dev/null || echo 0)"
  HELD="$(printf '%s' "$AUTO_JSON" | jq -r '.held // 0' 2>/dev/null || echo 0)"
  [[ "$APPLIED" =~ ^[0-9]+$ ]] || APPLIED=0
  [[ "$REVERTED" =~ ^[0-9]+$ ]] || REVERTED=0
  [[ "$HELD" =~ ^[0-9]+$ ]] || HELD=0
  [[ -n "$PERKEY" ]] || PERKEY="[]"
fi

# Learning report finding count (### headers).
REPORT_EXISTS=false; FINDING_COUNT=0
if [[ -f "$REPORT" ]]; then
  REPORT_EXISTS=true
  FINDING_COUNT="$(grep -cE '^### ' "$REPORT" 2>/dev/null)"
  [[ "$FINDING_COUNT" =~ ^[0-9]+$ ]] || FINDING_COUNT=0
fi

# Recent learning-apply decisions (last 5 `## ` headers).
RECENT="[]"
if [[ -f "$DECISIONS" ]]; then
  RECENT="$(grep -E '^## ' "$DECISIONS" 2>/dev/null | sed 's/^## //' | tail -5 \
    | jq -R . | jq -s . 2>/dev/null || echo "[]")"
  [[ -n "$RECENT" ]] || RECENT="[]"
fi

# Sprint 30-A: phase-runner progress (from the Sprint-21 ledger).
LEDGER="$STATE_DIR/phase-runner-progress.json"
PHASERUNNER="null"
if [[ -f "$LEDGER" ]]; then
  PHASERUNNER="$(jq -c '{phase:(.phase // ""), status:(.status // ""),
    currentStep:(.currentStep // ""), attempt:(.attempt // 1),
    maxConvergenceAttempts:(.maxConvergenceAttempts // 0),
    stepsDone:((.steps // []) | map(select(.status=="done")) | length),
    stepsTotal:((.steps // []) | length)}' "$LEDGER" 2>/dev/null || echo "null")"
  [[ -n "$PHASERUNNER" ]] || PHASERUNNER="null"
fi

# Sprint 30-A: cross-project signal (only when globalLearning.enabled).
CROSSPROJECT="null"
if [[ "$(vf_config_get '.globalLearning.enabled' 2>/dev/null || echo false)" == "true" ]]; then
  GLOBAL_FILE="$(vf_global_dir)/global-learning.jsonl"
  if [[ -f "$GLOBAL_FILE" ]]; then
    CROSSPROJECT="$(jq -s -c '
      {
        distinctProjects: ([.[].projectHash] | unique | length),
        perKey: (group_by(.key) | map(
          { key: .[0].key,
            projects: ([.[].projectHash] | unique | length),
            held: (map(select(.outcome=="held")) | length),
            reverted: (map(select(.outcome=="reverted")) | length) } as $o
          | { key: $o.key, projects: $o.projects,
              holdRate: (if ($o.held + $o.reverted) > 0
                         then (($o.held / ($o.held + $o.reverted)) * 100 | round) / 100 else 0 end) }))
      }' "$GLOBAL_FILE" 2>/dev/null || echo "null")"
    [[ -n "$CROSSPROJECT" ]] || CROSSPROJECT="null"
  fi
fi

jq -n -c \
  --argjson applied "$APPLIED" --argjson reverted "$REVERTED" --argjson held "$HELD" \
  --argjson armed "$ARMED" --argjson cooldowns "$COOLDOWNS" --argjson perkey "$PERKEY" \
  --argjson reportExists "$REPORT_EXISTS" --argjson findingCount "$FINDING_COUNT" \
  --argjson recent "$RECENT" --argjson phaseRunner "$PHASERUNNER" --argjson crossProject "$CROSSPROJECT" \
  '{autoApply:{applied:$applied, reverted:$reverted, held:$held, armedWatch:$armed, cooldowns:$cooldowns},
    perKey:$perkey,
    learning:{reportExists:$reportExists, findingCount:$findingCount},
    recentDecisions:$recent,
    phaseRunner:$phaseRunner,
    crossProject:$crossProject}' 2>/dev/null || echo "$EMPTY"
