#!/bin/bash
# Sprint 49 integration harness — sdlc_satisfy_criterion normalizes HTML entities
# so a criterion escaped in transit (testability.score&gt;=60) matches the literal
# exit gate (testability.score>=60). Otherwise advance stays blocked despite
# "satisfied" — bites any criterion containing > / < / &.
#
# Sections:
#   [S49-A] engine normalizes the criterion (helper + applied + unit test + live)
#   [S49-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

ENG="$REPO_ROOT/mcp-servers/sdlc-engine"

# ---------------------------------------------------------------------------
echo "== [S49-A] engine normalizes the criterion name =="

assert_grep "[S49-A] normalizeCriterion helper exists" "function normalizeCriterion" "$ENG/src/engine.ts"
assert_grep "[S49-A] decodes &gt;" 'replace\(/&gt;/g, ">"\)' "$ENG/src/engine.ts"
assert_grep "[S49-A] decodes &lt;" 'replace\(/&lt;/g, "<"\)' "$ENG/src/engine.ts"
assert_grep "[S49-A] decodes &amp; last" 'replace\(/&amp;/g, "&"\)' "$ENG/src/engine.ts"
assert_grep "[S49-A] satisfyCriterion applies normalizeCriterion" \
  "const criterion = normalizeCriterion\(input.criterion\)" "$ENG/src/engine.ts"
assert_grep "[S49-A] stores the normalized criterion (not the raw input)" \
  "satisfiedCriteria: \[\.\.\.base.satisfiedCriteria, criterion\]" "$ENG/src/engine.ts"
assert_grep "[S49-A] unit test covers the HTML-escaped criterion" \
  "normalizes HTML entities to match the literal" "$ENG/tests/engine.test.ts"

# Live: build + run unit tests, then a direct normalization probe against dist.
if (cd "$ENG" && npm run build >/dev/null 2>&1 && npm test >/tmp/s49_eng.log 2>&1); then
  pass "[S49-A] engine builds + all unit tests pass (incl. normalization)"
else
  fail "[S49-A] engine builds + unit tests pass (see /tmp/s49_eng.log)"
fi
# Node probe: import the built helper and confirm the canonical form.
PROBE="$(cd "$ENG" && node -e '
import("./dist/engine.js").then(m => {
  const n = m.normalizeCriterion;
  const out = [n("testability.score&gt;=60"), n("a&lt;b"), n("x&amp;y"), n("  p.q  ")].join("|");
  process.stdout.write(out);
}).catch(e => { process.stdout.write("ERR:"+e.message); });' 2>/dev/null)"
if [[ "$PROBE" == "testability.score>=60|a<b|x&y|p.q" ]]; then
  pass "[S49-A] live probe — normalizeCriterion canonicalizes &gt;/&lt;/&amp; + trims ($PROBE)"
else
  fail "[S49-A] live probe — normalizeCriterion (got '$PROBE')"
fi

# ---------------------------------------------------------------------------
echo "== [S49-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-49.sh"
assert_grep "[S49-Z] sprint-49.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S49-Z] covers [S49-A]" '\[S49-A\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
