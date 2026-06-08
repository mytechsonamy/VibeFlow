#!/bin/bash
# Sprint 43 integration harness — analyzers arm the consensus marker ONLY on a
# PASS verdict. A failing/blocked analyzer run must not arm the marker, because
# consensus-gate would then block the operator's next tool call — i.e. block the
# very iteration needed to fix the gap (add tests, install the mutation runner).
#
# Sections:
#   [S43-A] coverage-analyzer arms only on PASS
#   [S43-B] mutation-test-runner arms only on PASS
#   [S43-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

COV="$REPO_ROOT/skills/coverage-analyzer/SKILL.md"
MUT="$REPO_ROOT/skills/mutation-test-runner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S43-A] coverage-analyzer arms only on PASS =="

assert_grep "[S43-A] Final Step is conditioned on PASS" \
  'only on PASS|only if .VERDICT == .PASS.' "$COV"
assert_grep "[S43-A] names the arm-on-pass gate (Sprint 43)" "Arm-on-pass gate" "$COV"
assert_grep "[S43-A] non-PASS does NOT write the marker" \
  "do \\*\\*not\\*\\* write the marker|nothing to send to consensus" "$COV"
assert_grep "[S43-A] explains it would otherwise block the fix iteration" \
  "block the.*iteration|block the operator|block the very" "$COV"
assert_grep "[S43-A] still writes the marker JSON on PASS (schema preserved)" \
  '"createdBy": "coverage-analyzer"' "$COV"

# ---------------------------------------------------------------------------
echo "== [S43-B] mutation-test-runner arms only on PASS =="

assert_grep "[S43-B] Final Step is conditioned on PASS" \
  'only on PASS|only if .VERDICT == .PASS.' "$MUT"
assert_grep "[S43-B] names the arm-on-pass gate (Sprint 43)" "Arm-on-pass gate" "$MUT"
assert_grep "[S43-B] non-PASS does NOT write the marker" \
  "do \\*\\*not\\*\\* write the marker|nothing to send to consensus" "$MUT"
assert_grep "[S43-B] calls out the no-runner / BLOCKED case explicitly" \
  "no mutation runner is installed|P0 mutant survived|installing the runner" "$MUT"
assert_grep "[S43-B] still writes the marker JSON on PASS (schema preserved)" \
  '"createdBy": "mutation-test-runner"' "$MUT"

# ---------------------------------------------------------------------------
echo "== [S43-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-43.sh"
assert_grep "[S43-Z] sprint-43.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S43-Z] covers [S43-A]" '\[S43-A\]' "$SELF"
assert_grep "[S43-Z] covers [S43-B]" '\[S43-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
