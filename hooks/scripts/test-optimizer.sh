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
CACHE="$STATE_DIR/test-mapping.cache.json"

if [[ ! -f "$LOG" ]]; then
  # No trace yet — run everything. Clear any stale hint.
  rm -f "$HINT"
  echo '{"continue": true}'
  exit 0
fi

# Pull the last ~100 edits. Each line is "ts<TAB>phase<TAB>path".
RECENT="$(tail -n 100 "$LOG" | awk -F '\t' '{print $3}' | sort -u)"

# Resolved test mapping is cached in $CACHE as JSON:
#   { "<src>": { "test": "<path>", "mtime": <seconds> } }
# An entry is reused when the source file's mtime is <= the cached mtime.
# A stale entry (newer source mtime) forces re-resolution. A missing
# source file evicts the entry.
CACHE_GET() {
  local src="$1"
  vf_have_jq || return 1
  [[ -f "$CACHE" ]] || return 1
  jq -r --arg s "$src" '.[$s].test // empty' "$CACHE" 2>/dev/null
}

CACHE_MTIME() {
  local src="$1"
  vf_have_jq || return 1
  [[ -f "$CACHE" ]] || return 1
  jq -r --arg s "$src" '.[$s].mtime // empty' "$CACHE" 2>/dev/null
}

file_mtime() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo ""
    return
  fi
  # Portable: stat formats differ between BSD (macOS) and GNU (Linux).
  if stat -f '%m' "$f" >/dev/null 2>&1; then
    stat -f '%m' "$f"
  else
    stat -c '%Y' "$f" 2>/dev/null || echo ""
  fi
}

cache_set() {
  local src="$1" resolved="$2" mtime="$3"
  vf_have_jq || return 0
  [[ -f "$CACHE" ]] || echo "{}" > "$CACHE"
  jq --arg s "$src" --arg t "$resolved" --argjson m "$mtime" \
     '. + {($s): {test: $t, mtime: $m}}' "$CACHE" > "$CACHE.tmp" \
    && mv "$CACHE.tmp" "$CACHE"
}

cache_del() {
  local src="$1"
  vf_have_jq || return 0
  [[ -f "$CACHE" ]] || return 0
  jq --arg s "$src" 'del(.[$s])' "$CACHE" > "$CACHE.tmp" \
    && mv "$CACHE.tmp" "$CACHE"
}

CANDIDATES=()
while IFS= read -r src; do
  [[ -z "$src" ]] && continue

  # Skip paths that already look like tests.
  if [[ "$src" =~ (\.test\.|\.spec\.|/tests?/) ]]; then
    [[ -f "$src" ]] && CANDIDATES+=("$src")
    continue
  fi

  SRC_MTIME="$(file_mtime "$src")"
  if [[ -z "$SRC_MTIME" ]]; then
    # Source file disappeared (rename, delete). Drop any stale cache
    # entry and skip.
    cache_del "$src"
    continue
  fi

  # Cache hit: cached mtime matches current mtime → reuse resolution.
  CACHED_TEST="$(CACHE_GET "$src" 2>/dev/null || true)"
  CACHED_MTIME="$(CACHE_MTIME "$src" 2>/dev/null || true)"
  if [[ -n "$CACHED_TEST" && "$CACHED_MTIME" == "$SRC_MTIME" && -f "$CACHED_TEST" ]]; then
    CANDIDATES+=("$CACHED_TEST")
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
  RESOLVED=""
  for t in "${tries[@]}"; do
    if [[ -f "$t" ]]; then
      RESOLVED="$t"
      CANDIDATES+=("$t")
      break
    fi
  done
  if [[ -n "$RESOLVED" ]]; then
    cache_set "$src" "$RESOLVED" "$SRC_MTIME"
  else
    # Source exists but no test was found. Evict any stale cache entry
    # so a later test file creation can be picked up.
    cache_del "$src"
  fi
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
