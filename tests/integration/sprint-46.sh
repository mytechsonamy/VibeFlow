#!/bin/bash
# Sprint 46 integration harness — cycle-completion clarity. A merged PR / reaching
# DEPLOYMENT is NOT cycle completion; only DEPLOYMENT GO is. An in-progress cycle
# (even parked at DEPLOYMENT) resumes — never a new increment / brownfield.
#
# Sections:
#   [S46-A] phase-runner: completion clarity + no new-increment for in-progress
#   [S46-B] phase-runner: stuck-DEPLOYMENT (no infra) guidance
#   [S46-C] onboard + docs completion clarity
#   [S46-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
ONB="$REPO_ROOT/skills/onboard/SKILL.md"
DOC="$REPO_ROOT/docs/LIFECYCLE.md"

# ---------------------------------------------------------------------------
echo "== [S46-A] phase-runner completion clarity =="

assert_grep "[S46-A] a merged PR is NOT completion" \
  "A merged PR does not" "$RUNNER"
assert_grep "[S46-A] reaching DEPLOYMENT is NOT completion" \
  "reached DEPLOYMENT.*the last phase|reaching DEPLOYMENT" "$RUNNER"
assert_grep "[S46-A] completed flips only on DEPLOYMENT GO" \
  "flips \\*\\*only\\*\\* on DEPLOYMENT GO|only.*on DEPLOYMENT GO" "$RUNNER"
assert_grep "[S46-A] never new-increment for an in-progress cycle" \
  "Never narrate or breadcrumb.*next increment|for an .in-progress. cycle" "$RUNNER"
assert_grep "[S46-A] in-progress holds at DEPLOYMENT (resume there)" \
  "holds at DEPLOYMENT|in-progress cycle sitting at DEPLOYMENT" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S46-B] stuck-DEPLOYMENT guidance =="

assert_grep "[S46-B] names the can't-reach-GO (no infra) case" \
  "can't reach GO|no real CI / deploy / health infra|deployment.verified needs" "$RUNNER"
assert_grep "[S46-B] option 1 — finish the deploy" "Finish the deploy" "$RUNNER"
assert_grep "[S46-B] option 2 — operator explicitly closes/defers" \
  "Explicitly close/defer|operator. sets .currentCycle.status|deploy deferred" "$RUNNER"
assert_grep "[S46-B] do NOT auto-start a new increment to move on" \
  "Do \\*\\*not\\*\\* auto-start a new increment|silently abandons" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S46-C] onboard + docs completion clarity =="

assert_grep "[S46-C] onboard: completed = literal status, not merged PR" \
  "literal status field|not.*the PR was merged" "$ONB"
assert_grep "[S46-C] onboard: in-progress at DEPLOYMENT routes to resume" \
  "parked at DEPLOYMENT.*still|routes to \\*\\*resume\\*\\*" "$ONB"
assert_grep "[S46-C] docs have the completion-clarity / trap section" \
  "What .completed. means|common trap|trap to avoid" "$DOC"
assert_grep "[S46-C] docs: merged PR / reached DEPLOYMENT are not completion" \
  "merged to main|reached DEPLOYMENT" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S46-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-46.sh"
assert_grep "[S46-Z] sprint-46.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S46-Z] covers [S46-A]" '\[S46-A\]' "$SELF"
assert_grep "[S46-Z] covers [S46-B]" '\[S46-B\]' "$SELF"
assert_grep "[S46-Z] covers [S46-C]" '\[S46-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
