#!/bin/bash
# Sprint 64 integration harness — deterministic single-step `▶ Next:` breadcrumbs
# are also presented as a tappable "Run <command> now / Not yet" AskUserQuestion.
#
# Sections:
#   [S64-A] every breadcrumb-emitting skill: AskUserQuestion in allowed-tools +
#           the "Breadcrumb as a tappable card" block (Run-now / Not-yet)
#   [S64-B] docs/OPERATOR-CHOICES.md documents the single-deterministic-next rule
#   [S64-C] the buggy `allowed-tools:[^\n]*` sentinels were corrected to `.*`
#   [S64-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

DOC="$REPO_ROOT/docs/OPERATOR-CHOICES.md"

# Every skill that ends with a ▶ Next: breadcrumb.
SKILLS="architecture-bootstrap brownfield-intake coverage-analyzer design-bootstrap frontend-render-check input-validation-matrix integrate integration-verifier mobile-stability-runner mutation-test-runner onboard phase-runner prd-quality-analyzer"

# ---------------------------------------------------------------------------
echo "== [S64-A] breadcrumb-emitting skills present a Run-now/Not-yet card =="

for s in $SKILLS; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  # the skill must still emit a ▶ Next breadcrumb (the precondition)
  assert_grep "[S64-A] $s emits a ▶ Next breadcrumb" "▶ Next" "$f"
  # AskUserQuestion granted
  assert_grep "[S64-A] $s allowed-tools has AskUserQuestion" "^allowed-tools:.*AskUserQuestion" "$f"
  # the Sprint-64 breadcrumb-card block
  assert_grep "[S64-A] $s has the breadcrumb-card block" "Breadcrumb as a tappable card" "$f"
  # the Run-now / Not-yet shape
  assert_grep "[S64-A] $s offers Run-now + Not-yet" "Not yet" "$f"
done

# ---------------------------------------------------------------------------
echo "== [S64-B] OPERATOR-CHOICES.md documents the single-deterministic-next rule =="

assert_grep "[S64-B] documents single deterministic next command is a card" "single deterministic next command is a card" "$DOC"
assert_grep "[S64-B] names the Run-now (Recommended) option" "Run .* now \\(Recommended\\)" "$DOC"
assert_grep "[S64-B] keeps the breadcrumb as fallback" "textual fallback" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S64-C] buggy allowed-tools:[^\\n]* sentinels corrected =="

# The `[^\n]` idiom matched "not backslash-or-n" (not "not newline"), so an
# allowed-tools value containing a literal 'n' before Write/Edit (e.g.
# AskUserQuestion) defeated the check. They must now use `.*`.
if grep -rn 'allowed-tools:\[\^\\n\]' "$REPO_ROOT"/tests/integration/*.sh 2>/dev/null | grep -v 'sprint-64.sh:' >/dev/null 2>&1; then
  fail "[S64-C] no allowed-tools:[^\\n]* sentinels remain"
else
  pass "[S64-C] no allowed-tools:[^\\n]* sentinels remain"
fi
assert_grep "[S64-C] sprint-14 uses allowed-tools:.* form" "allowed-tools:\\.\\*" "$REPO_ROOT/tests/integration/sprint-14.sh"

# ---------------------------------------------------------------------------
echo "== [S64-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-64.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S64-Z] shebang #!/bin/bash"; else fail "[S64-Z] shebang #!/bin/bash"; fi
for sec in S64-A S64-B S64-C S64-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S64-Z] [$sec] section header present"; else fail "[S64-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
