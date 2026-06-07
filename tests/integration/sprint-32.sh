#!/bin/bash
# Sprint 32 integration harness — command-collision audit + status→flow-status.
#
# Sections:
#   [S32-A] status → flow-status rename completeness
#   [S32-B] zero exact collisions between skill names and Claude built-ins
#   [S32-C] docs (COMMAND-COLLISIONS.md) + stale /vibeflow:review removed
#   [S32-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

FS="$REPO_ROOT/skills/flow-status/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"

# ---------------------------------------------------------------------------
echo "== [S32-A] status → flow-status rename completeness =="

assert_file "[S32-A] skills/flow-status/SKILL.md exists" "$FS"
if [[ ! -d "$REPO_ROOT/skills/status" ]]; then
  pass "[S32-A] skills/status/ removed"
else
  fail "[S32-A] skills/status/ removed (still present)"
fi
assert_grep "[S32-A] flow-status frontmatter name: flow-status" "^name: flow-status$" "$FS"

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["flow-status"] != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S32-A] phase-policy registers flow-status"
  else
    fail "[S32-A] phase-policy registers flow-status"
  fi
  if jq -e '.skills.status == null' "$POLICY" >/dev/null 2>&1; then
    pass "[S32-A] phase-policy no longer registers status"
  else
    fail "[S32-A] phase-policy no longer registers status"
  fi
fi

# No FUNCTIONAL references to the retired bare `vibeflow:status` in skills or
# hooks (where a stale ref would actually mis-invoke). Docs may legitimately
# mention the old name to *document* the rename (COMMAND-COLLISIONS.md, the
# CLAUDE.md "Renamed from …" line), and the loop-status / flow-status tokens
# are different substrings.
LIVE="$(grep -rln "vibeflow:status" "$REPO_ROOT/skills" "$REPO_ROOT/hooks" 2>/dev/null || true)"
if [[ -z "$LIVE" ]]; then
  pass "[S32-A] no functional (skills/hooks) /vibeflow:status references remain"
else
  fail "[S32-A] no functional /vibeflow:status references remain (found: $LIVE)"
fi
# No skills/status/ path references in skills or hooks.
LIVE_PATH="$(grep -rln "skills/status/" "$REPO_ROOT/skills" "$REPO_ROOT/hooks" 2>/dev/null || true)"
if [[ -z "$LIVE_PATH" ]]; then
  pass "[S32-A] no skills/status/ path references in skills/hooks"
else
  fail "[S32-A] no skills/status/ path references in skills/hooks (found: $LIVE_PATH)"
fi
# loop-status survived the rename untouched.
assert_file "[S32-A] loop-status skill kept" "$REPO_ROOT/skills/loop-status/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S32-B] zero exact collisions: skill names vs Claude built-ins =="

# Authoritative built-in set (bare slash-command names). Keep in sync with
# docs/COMMAND-COLLISIONS.md.
BUILTINS="help clear compact config cost status doctor login logout model memory mcp agents hooks permissions bug release-notes resume export vim terminal-setup add-dir init review run fast upgrade pr-comments feedback privacy-settings verify code-review simplify schedule loop"
COLLISIONS=0
for d in "$REPO_ROOT"/skills/*/; do
  n="$(grep -m1 '^name:' "$d/SKILL.md" 2>/dev/null | sed 's/^name:[[:space:]]*//')"
  [[ -n "$n" ]] || continue
  for b in $BUILTINS; do
    if [[ "$n" == "$b" ]]; then
      fail "[S32-B] skill '$n' collides with built-in /$b"
      COLLISIONS=$((COLLISIONS + 1))
    fi
  done
done
if (( COLLISIONS == 0 )); then
  pass "[S32-B] no skill name exactly collides with a Claude Code built-in"
fi
# Pin the two known historical offenders are gone by name.
for retired in status init; do
  if [[ ! -d "$REPO_ROOT/skills/$retired" ]]; then
    pass "[S32-B] retired skill name '$retired' has no directory"
  else
    fail "[S32-B] retired skill name '$retired' still has a directory"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S32-C] docs + stale review cleanup =="

assert_file "[S32-C] docs/COMMAND-COLLISIONS.md exists" "$REPO_ROOT/docs/COMMAND-COLLISIONS.md"
assert_grep "[S32-C] audit doc names the flow-status rename" \
  "flow-status" "$REPO_ROOT/docs/COMMAND-COLLISIONS.md"
assert_grep "[S32-C] CLAUDE.md Key Commands lists flow-status" \
  "vibeflow:flow-status" "$REPO_ROOT/CLAUDE.md"
# The Key Commands section must not list a `/vibeflow:review` command bullet
# (the ledger may *document* the removal, mentioning the old name in prose —
# that's allowed; only an actual command-listing bullet is stale).
if ! grep -qE '^- `/vibeflow:review`' "$REPO_ROOT/CLAUDE.md"; then
  pass "[S32-C] no stale /vibeflow:review command bullet in CLAUDE.md Key Commands"
else
  fail "[S32-C] no stale /vibeflow:review command bullet in CLAUDE.md Key Commands"
fi

# ---------------------------------------------------------------------------
echo "== [S32-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-32.sh"
assert_grep "[S32-Z] sprint-32.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S32-Z] covers [S32-A]" '\[S32-A\]' "$SELF"
assert_grep "[S32-Z] covers [S32-B]" '\[S32-B\]' "$SELF"
assert_grep "[S32-Z] covers [S32-C]" '\[S32-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
