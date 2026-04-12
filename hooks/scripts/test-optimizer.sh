#!/bin/bash
# VibeFlow Test Optimizer Hook (PreToolUse / Bash / npm test|vitest|jest).
#
# Reads .vibeflow/traces/changed-files.log (written by post-edit.sh) and maps
# recently-changed source files to candidate test files using conventional
# name patterns. Writes the candidate list to
# .vibeflow/state/next-test-hint.json so commands like /vibeflow:status can
# surface it. This is a non-blocking hint: we never rewrite the user's test
# command, since a false negative here would silently skip coverage.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cat >/dev/null || true

LOG="$(vf_traces_dir)/changed-files.log"
STATE_DIR="$(vf_state_dir)"
HINT="$STATE_DIR/next-test-hint.json"

if [[ ! -f "$LOG" ]]; then
  # No trace yet — run everything. Clear any stale hint.
  rm -f "$HINT"
  echo '{"continue": true}'
  exit 0
fi

# Pull the last ~100 edits. Each line is "ts<TAB>phase<TAB>path".
RECENT="$(tail -n 100 "$LOG" | awk -F '\t' '{print $3}' | sort -u)"

CANDIDATES=()
while IFS= read -r src; do
  [[ -z "$src" ]] && continue

  # Skip paths that already look like tests.
  if [[ "$src" =~ (\.test\.|\.spec\.|/tests?/) ]]; then
    [[ -f "$src" ]] && CANDIDATES+=("$src")
    continue
  fi

  base="${src##*/}"                       # foo.ts
  dir="${src%/*}"                         # path/to
  stem="${base%.*}"                       # foo
  ext="${base##*.}"                       # ts

  # Try common test patterns, in order of specificity.
  tries=(
    "$dir/$stem.test.$ext"
    "$dir/$stem.spec.$ext"
    "$dir/__tests__/$stem.test.$ext"
    "${dir/\/src\//\/tests\/}/$stem.test.$ext"
    "${dir/\/src\//\/test\/}/$stem.test.$ext"
  )
  for t in "${tries[@]}"; do
    if [[ -f "$t" ]]; then
      CANDIDATES+=("$t")
      break
    fi
  done
done <<< "$RECENT"

# Deduplicate while preserving order (no assoc-array dependency — bash 3.2
# compatible for default macOS shells).
if ((${#CANDIDATES[@]} > 0)); then
  UNIQUE=()
  for c in "${CANDIDATES[@]}"; do
    dup=0
    for u in "${UNIQUE[@]:-}"; do
      if [[ "$u" == "$c" ]]; then dup=1; break; fi
    done
    (( dup == 0 )) && UNIQUE+=("$c")
  done
  CANDIDATES=("${UNIQUE[@]}")
fi

if vf_have_jq; then
  printf '%s\n' "${CANDIDATES[@]:-}" \
    | jq -R -s -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      'split("\n") | map(select(length > 0)) as $c | {generatedAt:$ts, candidates:$c, count:($c|length)}' \
    > "$HINT"
fi

echo '{"continue": true}'
exit 0
