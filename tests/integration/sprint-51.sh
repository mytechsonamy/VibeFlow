#!/bin/bash
# Sprint 51 integration harness — phase-write-guard source patterns are
# monorepo-aware. `src/**` only matches top-level src, so a monorepo source file
# (packages/*/src/…, apps/*/src/…) matched neither allow nor the source `warn`
# and fell to a hard BLOCK in TESTING — even for a legitimate touch like a
# Stryker equivalent-mutant annotation. Adding `**/src/**` to the warn list
# makes monorepo source a warn (soft-allow), consistent with top-level.
#
# Sections:
#   [S51-A] policy adds **/src/** to TESTING + DEPLOYMENT warn
#   [S51-B] runtime — monorepo source warns; non-src blocks; REQUIREMENTS unchanged
#   [S51-C] docs note the monorepo-aware source paths
#   [S51-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

POLICY="$REPO_ROOT/hooks/scripts/phase-policy.json"
DOC="$REPO_ROOT/docs/PHASE-BOUNDARIES.md"

# ---------------------------------------------------------------------------
echo "== [S51-A] policy adds **/src/** to TESTING + DEPLOYMENT warn =="

if command -v jq >/dev/null 2>&1; then
  for ph in TESTING DEPLOYMENT; do
    if jq -e --arg p "$ph" '.phases[$p].warn | index("**/src/**") != null' "$POLICY" >/dev/null 2>&1; then
      pass "[S51-A] $ph warn includes **/src/**"
    else
      fail "[S51-A] $ph warn includes **/src/**"
    fi
    if jq -e --arg p "$ph" '.phases[$p].warn | index("src/**") != null' "$POLICY" >/dev/null 2>&1; then
      pass "[S51-A] $ph warn keeps top-level src/**"
    else
      fail "[S51-A] $ph warn keeps top-level src/**"
    fi
  done
fi

# ---------------------------------------------------------------------------
echo "== [S51-B] runtime — the matcher's decisions =="

decide() {  # phase, relpath → allow|warn|block
  ( cd "$REPO_ROOT" && bash -c 'source hooks/scripts/_lib.sh 2>/dev/null; vf_phase_decision "$1" "$2" "hooks/scripts/phase-policy.json"' _ "$1" "$2" )
}

[[ "$(decide TESTING packages/shared/src/dashboard.ts)" == "warn" ]] \
  && pass "[S51-B] TESTING monorepo source (packages/*/src) → warn (soft-allow)" \
  || fail "[S51-B] TESTING monorepo source → warn (got '$(decide TESTING packages/shared/src/dashboard.ts)')"
[[ "$(decide TESTING apps/web/src/x.ts)" == "warn" ]] \
  && pass "[S51-B] TESTING apps/*/src source → warn" || fail "[S51-B] TESTING apps/*/src → warn"
[[ "$(decide TESTING src/top.ts)" == "warn" ]] \
  && pass "[S51-B] TESTING top-level src → warn (unchanged)" || fail "[S51-B] TESTING top-level src → warn"
[[ "$(decide TESTING packages/shared/src/dashboard.test.ts)" == "allow" ]] \
  && pass "[S51-B] TESTING monorepo test file → allow" || fail "[S51-B] TESTING monorepo test file → allow"
[[ "$(decide TESTING packages/shared/lib/logic.ts)" == "block" ]] \
  && pass "[S51-B] TESTING non-src monorepo path (lib) → block (not over-permissive)" \
  || fail "[S51-B] TESTING non-src (lib) → block (got '$(decide TESTING packages/shared/lib/logic.ts)')"
[[ "$(decide REQUIREMENTS packages/shared/src/dashboard.ts)" == "block" ]] \
  && pass "[S51-B] REQUIREMENTS monorepo source → block (no regression)" \
  || fail "[S51-B] REQUIREMENTS monorepo source → block"

# ---------------------------------------------------------------------------
echo "== [S51-C] docs =="

assert_grep "[S51-C] PHASE-BOUNDARIES notes monorepo-aware source paths" \
  "Monorepo-aware source paths|\\*\\*/src/\\*\\*" "$DOC"
assert_grep "[S51-C] PHASE-BOUNDARIES names the Stryker equivalent-mutant case" \
  "Stryker|equivalent mutant" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S51-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-51.sh"
assert_grep "[S51-Z] sprint-51.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S51-Z] covers [S51-A]" '\[S51-A\]' "$SELF"
assert_grep "[S51-Z] covers [S51-B]" '\[S51-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
