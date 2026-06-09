#!/bin/bash
# Sprint 52 integration harness — phase-runner Step 0 surfaces in-flight work
# (uncommitted changes + a review-pending marker) before progressing, so
# "run phase-runner" doesn't silently advance past unreviewed work — especially
# into DEVELOPMENT, whose code.reviewed runs on the committed diff. Surface-only:
# never auto-commits, never blocks.
#
# Sections:
#   [S52-A] phase-runner surfaces pending work in Step 0
#   [S52-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S52-A] phase-runner surfaces pending work before progressing =="

assert_grep "[S52-A] Step 0 has a Surface-pending-work section" \
  "Surface pending work before progressing" "$RUNNER"
assert_grep "[S52-A] clarifies phase-runner does not commit/push" \
  "does \\*\\*not\\*\\* commit/push|not .commit everything and ship" "$RUNNER"
assert_grep "[S52-A] checks git status --porcelain for uncommitted changes" \
  "git status --porcelain" "$RUNNER"
assert_grep "[S52-A] checks the review-pending marker" \
  "review-pending\.json|trigger-ai-review" "$RUNNER"
assert_grep "[S52-A] explains uncommitted work is skipped by the DEVELOPMENT diff review" \
  "not.*reviewed|won't be in the DEVELOPMENT review diff|committed.*diff" "$RUNNER"
assert_grep "[S52-A] surface-only — does NOT block + does NOT auto-commit" \
  "does \\*\\*not block\\*\\*|never auto-commit|surfaces it so" "$RUNNER"
assert_grep "[S52-A] stays quiet when nothing is pending" \
  "say nothing" "$RUNNER"
assert_grep "[S52-A] allowed-tools include git status (read-only)" \
  "Bash\\(git status\\*\\)" "$RUNNER"

# A guard against scope-creep: phase-runner must not auto-commit. There should be
# no `git commit` / `git add` in an allowed-tools or an instruction to run them.
if ! grep -qE 'Bash\(git (add|commit|push)' "$RUNNER"; then
  pass "[S52-A] phase-runner does not allow git add/commit/push (surface-only)"
else
  fail "[S52-A] phase-runner must not allow git add/commit/push"
fi

# ---------------------------------------------------------------------------
echo "== [S52-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-52.sh"
assert_grep "[S52-Z] sprint-52.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S52-Z] covers [S52-A]" '\[S52-A\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
