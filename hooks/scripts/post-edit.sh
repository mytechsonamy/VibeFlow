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
if [[ "$FILE_PATH" =~ \.(md|json|yaml|yml|toml|lock|log|db|svg|png|jpg|gif|ico|woff2?|ttf|eot|otf)$ ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Skip dotfiles that are not tracked source (env, OS metadata, editor temps).
# Matches: basename starting with a dot, common editor swap/backup files,
# and the macOS .DS_Store tombstone.
BASENAME="${FILE_PATH##*/}"
if [[ "$BASENAME" == ".env"* \
   || "$BASENAME" == ".DS_Store" \
   || "$BASENAME" == ".#"* \
   || "$BASENAME" == "#"*"#" \
   || "$BASENAME" == *"~" \
   || "$BASENAME" =~ \.swp$ \
   || "$BASENAME" =~ \.swo$ ]]; then
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

# Debounce: if the most recent log entry for this exact path is within 5
# seconds of now, skip the write. Prevents auto-save / format-on-save
# loops from hammering the log with duplicate rows. We still count the
# edit as observed, just not as a fresh datapoint.
#
# Implementation note: we read only the tail (20 lines) so the check stays
# cheap even on a 1000-line log.
DEBOUNCE_SECONDS=5
if [[ -f "$LOG" ]]; then
  LAST_TS="$(tail -n 20 "$LOG" \
    | awk -F '\t' -v path="$FILE_PATH" '$3 == path {last=$1} END{print last}')"
  if [[ -n "$LAST_TS" ]]; then
    # Convert both timestamps to unix seconds. Portable across macOS/Linux
    # without relying on GNU `date -d`; use python fallback when needed.
    NOW_EPOCH="$(date -u +%s)"
    LAST_EPOCH=""
    if command -v python3 >/dev/null 2>&1; then
      LAST_EPOCH="$(python3 -c "import datetime,sys;print(int(datetime.datetime.strptime('$LAST_TS','%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()))" 2>/dev/null || echo "")"
    fi
    if [[ -n "$LAST_EPOCH" ]] && (( NOW_EPOCH - LAST_EPOCH < DEBOUNCE_SECONDS )); then
      echo '{"continue": true}'
      exit 0
    fi
  fi
fi

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
