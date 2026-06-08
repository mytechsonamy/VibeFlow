#!/bin/bash
# Sprint 38 integration harness — no skill routes to the read-only Explore
# agent. `agent: Explore` in a skill's frontmatter ran it on the Explore agent,
# which CANNOT Write — so Write-needing analyzers/validators couldn't produce
# their report and came back as a bare codebase "exploration" instead of
# executing (the recurring architecture-validator / release-decision-engine
# "returned exploration" bug). All `agent: Explore` lines were removed.
#
# Sections:
#   [S38-A] no skill carries `agent: Explore`
#   [S38-B] Write-needing analyzers still execute-capable (Write + no Explore)
#   [S38-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

# ---------------------------------------------------------------------------
echo "== [S38-A] no skill routes to the read-only Explore agent =="

OFFENDERS="$(grep -rl '^agent: Explore$' "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null || true)"
if [[ -z "$OFFENDERS" ]]; then
  pass "[S38-A] no skill frontmatter carries 'agent: Explore'"
else
  fail "[S38-A] no skill carries 'agent: Explore' (offenders: $OFFENDERS)"
fi
# Belt-and-suspenders: any `agent:` directive pointing at a read-only agent is
# wrong for a Write-needing skill. We only ever set Explore historically, so
# pin that none remain.
if ! grep -rqE '^agent:[[:space:]]*Explore' "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null; then
  pass "[S38-A] no 'agent: Explore' directive anywhere under skills/"
else
  fail "[S38-A] no 'agent: Explore' directive anywhere under skills/"
fi

# ---------------------------------------------------------------------------
echo "== [S38-B] Write-needing analyzers can now execute =="

# These are the validators/analyzers that were silently failing; confirm each
# keeps Write (so it can produce its report) and no longer routes to Explore.
for s in architecture-validator prd-quality-analyzer test-strategy-planner \
         traceability-engine coverage-analyzer release-decision-engine; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  if grep -qE '^allowed-tools:.*\bWrite\b' "$f" 2>/dev/null \
     && ! grep -q '^agent: Explore$' "$f" 2>/dev/null; then
    pass "[S38-B] $s keeps Write + no Explore routing (can execute)"
  else
    fail "[S38-B] $s keeps Write + no Explore routing"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S38-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-38.sh"
assert_grep "[S38-Z] sprint-38.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S38-Z] covers [S38-A]" '\[S38-A\]' "$SELF"
assert_grep "[S38-Z] covers [S38-B]" '\[S38-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
