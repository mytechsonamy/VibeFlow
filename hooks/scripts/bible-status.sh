#!/usr/bin/env bash
# bible-status.sh (Sprint 68) — READ-ONLY: the state of the Product Bible.
#
# Cross-references the bible taxonomy (hooks/scripts/bible-manifest.json, or a
# project override at docs/product-bible/manifest.json) against the actual repo,
# and reports which canonical documents are present vs missing — so a project can
# see, at any point, how much of its "product bible" exists and what's still owed.
# Existing VibeFlow outputs (PRD/ADR/design-spec/test-strategy/…) are referenced
# in place (source:"vibeflow"), never duplicated.
#
# Output: one JSON object on stdout —
#   {"total":N,"present":N,"missing":N,
#    "byCategory":{"business":{...},"product":{...},"engineering":{...}},
#    "docs":[{"key","title","category","phase","lifecycle","source","status","path"}]}
# Fail-safe: any error / no jq ⇒ a minimal {"total":0,...} so callers never break.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"
set +e   # _lib.sh enables errexit; this reader uses non-zero find/grep as conditionals

EMPTY='{"total":0,"present":0,"missing":0,"byCategory":{},"docs":[]}'
vf_have_jq || { echo "$EMPTY"; exit 0; }

CWD="$(vf_cwd)"
# Project override wins over the plugin default taxonomy.
MANIFEST="$CWD/docs/product-bible/manifest.json"
[ -f "$MANIFEST" ] || MANIFEST="$SCRIPT_DIR/bible-manifest.json"
[ -f "$MANIFEST" ] || { echo "$EMPTY"; exit 0; }

# Resolve presence for one doc given its path + optional match regex.
#   - file path → exists?
#   - dir path + match → dir has ≥1 file matching the regex?
present_for() {
  local p="$1" match="$2"
  local abs="$CWD/$p"
  if [ -n "$match" ]; then
    # a directory (or a parent dir like "docs") scanned for a matching file
    if [ -d "$abs" ]; then
      find "$abs" -maxdepth 2 -type f 2>/dev/null | grep -qE "$match" && return 0
      return 1
    fi
    return 1
  fi
  [ -e "$abs" ] && return 0
  return 1
}

ROWS="[]"
# Iterate keys, then read each field via a dedicated jq -r lookup. (We avoid
# @tsv on purpose: it re-escapes backslashes, which corrupts the `match` regex —
# `\.md$` would arrive as `\\.md$` and never match.)
while read -r key; do
  [ -n "$key" ] || continue
  title="$(jq -r --arg k "$key" '.docs[$k].title // $k' "$MANIFEST")"
  category="$(jq -r --arg k "$key" '.docs[$k].category // ""' "$MANIFEST")"
  phase="$(jq -r --arg k "$key" '.docs[$k].phase // ""' "$MANIFEST")"
  lifecycle="$(jq -r --arg k "$key" '.docs[$k].lifecycle // ""' "$MANIFEST")"
  source="$(jq -r --arg k "$key" '.docs[$k].source // ""' "$MANIFEST")"
  path="$(jq -r --arg k "$key" '.docs[$k].path // ""' "$MANIFEST")"
  match="$(jq -r --arg k "$key" '.docs[$k].match // ""' "$MANIFEST")"
  if present_for "$path" "$match"; then status="present"; else status="missing"; fi
  row="$(jq -nc \
    --arg key "$key" --arg title "$title" --arg category "$category" \
    --arg phase "$phase" --arg lifecycle "$lifecycle" --arg source "$source" \
    --arg status "$status" --arg path "$path" \
    '{key:$key,title:$title,category:$category,phase:$phase,lifecycle:$lifecycle,source:$source,status:$status,path:$path}' 2>/dev/null)"
  [ -n "$row" ] && ROWS="$(echo "$ROWS" | jq -c --argjson r "$row" '. + [$r]' 2>/dev/null || echo "$ROWS")"
done < <(jq -r '.docs | keys[]' "$MANIFEST" 2>/dev/null)

# Aggregate.
echo "$ROWS" | jq '{
  total: length,
  present: (map(select(.status=="present")) | length),
  missing: (map(select(.status=="missing")) | length),
  byCategory: (group_by(.category) | map({key: .[0].category, value: {
      total: length,
      present: (map(select(.status=="present")) | length),
      missing: (map(select(.status=="missing")) | length)
    }}) | from_entries),
  docs: .
}' 2>/dev/null || echo "$EMPTY"
