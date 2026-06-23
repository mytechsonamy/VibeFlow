#!/bin/bash
# Sprint 63 integration harness — read-only status/dashboard views surface their
# closing "Next step" as a tappable AskUserQuestion choice (not prose).
#
# Sections:
#   [S63-A] flow-status / loop-status / streams: AskUserQuestion in allowed-tools
#           + a next-step-as-choice instruction (with a Stay/do-nothing option)
#   [S63-B] docs/OPERATOR-CHOICES.md documents the terminal-next-step rule + views
#   [S63-Z] harness self-audit

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
echo "== [S63-A] read-only views surface a tappable next-step =="

check_view() {
  local view="$1"
  local f="$REPO_ROOT/skills/$view/SKILL.md"
  assert_file "[S63-A] $view SKILL.md exists" "$f"
  assert_grep "[S63-A] $view allowed-tools has AskUserQuestion" "^allowed-tools:.*AskUserQuestion" "$f"
  # a next-step / operator-choice instruction that invokes AskUserQuestion in the body
  assert_grep "[S63-A] $view references the OPERATOR-CHOICES convention" "OPERATOR-CHOICES\\.md" "$f"
  assert_grep "[S63-A] $view names a tappable next step" "tappable" "$f"
  # always offers a Stay / do-nothing escape
  assert_grep "[S63-A] $view offers a Stay / do-nothing option" "Stay" "$f"
  # body actually invokes AskUserQuestion (not just frontmatter)
  local hits; hits="$(grep -c "AskUserQuestion" "$f")"
  if [[ "$hits" -ge 2 ]]; then pass "[S63-A] $view invokes AskUserQuestion in the body"; else fail "[S63-A] $view invokes AskUserQuestion in the body (hits=$hits)"; fi
}

check_view flow-status
check_view loop-status
check_view streams

# flow-status specifically must cover the advance / mismatch cases (the reported gap).
assert_grep "[S63-A] flow-status offers an advance next-step" "[Aa]dvance to" "$REPO_ROOT/skills/flow-status/SKILL.md"
assert_grep "[S63-A] flow-status offers a mismatch-fix next-step" "mismatch" "$REPO_ROOT/skills/flow-status/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S63-B] OPERATOR-CHOICES.md documents the terminal-next-step rule =="

assert_file "[S63-B] docs/OPERATOR-CHOICES.md exists" "$DOC"
assert_grep "[S63-B] documents terminal next-step breadcrumbs are tappable" "[Tt]erminal next-step breadcrumbs are tappable" "$DOC"
assert_grep "[S63-B] lists flow-status as a read-only view" "flow-status" "$DOC"
assert_grep "[S63-B] lists loop-status as a read-only view" "loop-status" "$DOC"
assert_grep "[S63-B] lists streams as a read-only view" "streams" "$DOC"
assert_grep "[S63-B] keeps the Stay / do-nothing guarantee" "Stay / do" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S63-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-63.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S63-Z] shebang #!/bin/bash"; else fail "[S63-Z] shebang #!/bin/bash"; fi
for sec in S63-A S63-B S63-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S63-Z] [$sec] section header present"; else fail "[S63-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
