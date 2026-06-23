#!/bin/bash
# Sprint 61 integration harness — operator decision points become tappable choices.
#
# Sections:
#   [S61-A] docs/OPERATOR-CHOICES.md convention + CLAUDE.md pointer
#   [S61-B] every operator-blocking skill: AskUserQuestion in allowed-tools
#           + an "Operator choice" block + the prose-menu fallback preserved
#   [S61-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

DOC="$REPO_ROOT/docs/OPERATOR-CHOICES.md"

# ---------------------------------------------------------------------------
echo "== [S61-A] convention doc + CLAUDE.md pointer =="

assert_file "[S61-A] docs/OPERATOR-CHOICES.md exists" "$DOC"
assert_grep "[S61-A] names the AskUserQuestion tool" "AskUserQuestion" "$DOC"
assert_grep "[S61-A] guarantees Other = still type" "Other" "$DOC"
assert_grep "[S61-A] recommended-option-first convention" "[Rr]ecommended" "$DOC"
assert_grep "[S61-A] mobile/remote rationale" "mobile|remote" "$DOC"
assert_grep "[S61-A] lists what stays a typed prompt" "typed prompt" "$DOC"
assert_grep "[S61-A] CLAUDE.md points at the convention" "OPERATOR-CHOICES\\.md" "$REPO_ROOT/CLAUDE.md"

# ---------------------------------------------------------------------------
echo "== [S61-B] operator-blocking skills surface tappable choices =="

# Each entry: skill | a regex that must still match the prose-menu fallback.
check_skill() {
  local skill="$1" fallback="$2"
  local f="$REPO_ROOT/skills/$skill/SKILL.md"
  assert_file "[S61-B] $skill SKILL.md exists" "$f"
  # (a) AskUserQuestion granted in frontmatter allowed-tools.
  assert_grep "[S61-B] $skill allowed-tools has AskUserQuestion" "^allowed-tools:.*AskUserQuestion" "$f"
  # (b) an operator-choice instruction references the convention.
  assert_grep "[S61-B] $skill references OPERATOR-CHOICES convention" "OPERATOR-CHOICES\\.md|Operator choice" "$f"
  # (b2) it actually names the AskUserQuestion tool in the body (not just frontmatter).
  local body_hits
  body_hits="$(grep -c "AskUserQuestion" "$f")"
  if [[ "$body_hits" -ge 2 ]]; then pass "[S61-B] $skill invokes AskUserQuestion in the body"; else fail "[S61-B] $skill invokes AskUserQuestion in the body (hits=$body_hits)"; fi
  # (c) the prose-menu / decision fallback is preserved.
  assert_grep "[S61-B] $skill keeps its decision fallback" "$fallback" "$f"
}

check_skill onboard                "[Dd]omain"
check_skill brownfield-intake      "Describe it"
check_skill design-bootstrap       "Claude-native"
check_skill architecture-bootstrap "Propose sensible defaults|Stack-agnostic"
check_skill apply-arbiter-patch    "Dry-run|dry-run"
check_skill phase-runner           "consensus-specialist"
check_skill integrate              "DEPLOYMENT"
check_skill release-decision-engine "GO|CONDITIONAL|BLOCKED"
check_skill learning-apply         "config-tune|Apply tune"

# No config flag was introduced (default-on is the whole point).
if grep -rqE "operatorChoices|operator_choices" "$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts" 2>/dev/null; then
  fail "[S61-B] no config flag introduced (default-on)"
else
  pass "[S61-B] no config flag introduced (default-on)"
fi

# ---------------------------------------------------------------------------
echo "== [S61-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-61.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S61-Z] shebang #!/bin/bash"; else fail "[S61-Z] shebang #!/bin/bash"; fi
for sec in S61-A S61-B S61-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S61-Z] [$sec] section header present"; else fail "[S61-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
