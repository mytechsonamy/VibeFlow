#!/bin/bash
# VibeFlow Post-Edit Hook (PostToolUse / Edit|Write).
#
# Appends every edited source file to .vibeflow/traces/changed-files.log as
# TSV: timestamp<TAB>phase<TAB>absolute_path. The log is the single source of
# truth for test-optimizer.sh (recent diffs → candidate tests) and the
# traceability-engine skill.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT="$(cat)"
FILE_PATH=""
if vf_have_jq; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"
fi

if [[ -z "$FILE_PATH" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Skip doc, data, and lockfile edits — nothing to trace for test selection.
if [[ "$FILE_PATH" =~ \.(md|json|yaml|yml|toml|lock|log|db|svg|png|jpg|gif)$ ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Skip files inside .vibeflow/ itself (our own state, never user source).
if [[ "$FILE_PATH" == *"/.vibeflow/"* ]]; then
  echo '{"continue": true}'
  exit 0
fi

LOG="$(vf_traces_dir)/changed-files.log"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PHASE="$(vf_current_phase)"
printf '%s\t%s\t%s\n' "$TS" "$PHASE" "$FILE_PATH" >> "$LOG"

# Cap the log at 1000 entries to keep reads fast. tail -n reads forward, so we
# use a temp file to replace atomically.
LINES="$(wc -l < "$LOG" | tr -d ' ')"
if (( LINES > 1000 )); then
  TMP="$LOG.tmp"
  tail -n 1000 "$LOG" > "$TMP" && mv "$TMP" "$LOG"
fi

echo '{"continue": true}'
exit 0
