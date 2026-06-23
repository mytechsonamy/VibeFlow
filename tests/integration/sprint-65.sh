#!/bin/bash
# Sprint 65 integration harness — ambient operator-choice convention on
# SessionStart, so ad-hoc questions the model poses while orchestrating (outside
# any skill) are nudged to render as tappable AskUserQuestion, not prose.
#
# Sections:
#   [S65-A] load-sdlc-context.sh emits the operator-choice convention line
#           (static sentinel + runtime probe)
#   [S65-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_contains() { local l="$1" needle="$2" hay="$3"; if [[ "$hay" == *"$needle"* ]]; then pass "$l"; else fail "$l (no '$needle')"; fi; }

LSC="$REPO_ROOT/hooks/scripts/load-sdlc-context.sh"

# ---------------------------------------------------------------------------
echo "== [S65-A] SessionStart operator-choice convention =="

assert_file "[S65-A] load-sdlc-context.sh exists" "$LSC"
assert_grep "[S65-A] emits the AskUserQuestion convention line" "AskUserQuestion tool" "$LSC"
assert_grep "[S65-A] convention is mobile/remote-first" "Mobile/remote-first" "$LSC"
assert_grep "[S65-A] documents the Sprint 65 rationale (ad-hoc questions)" "Sprint 65" "$LSC"

# Runtime: a clean project's SessionStart output carries the convention line.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s65-XXXXXX")"
printf '{"project":"acme","domain":"general","currentPhase":"DEVELOPMENT"}' > "$DIR/vibeflow.config.json"
OUT="$(VIBEFLOW_CWD="$DIR" bash "$LSC" 2>/dev/null)"
assert_contains "[S65-A] runtime: output nudges AskUserQuestion" "AskUserQuestion" "$OUT"
assert_contains "[S65-A] runtime: output names tappable options" "tappable options" "$OUT"
assert_contains "[S65-A] runtime: still prints the state line" "VibeFlow active" "$OUT"
# Bounded: the SessionStart context stays under the Sprint-65 budget.
LEN="${#OUT}"
if (( LEN <= 450 )); then pass "[S65-A] runtime: output within the 450-char budget (got $LEN)"; else fail "[S65-A] runtime: output within the 450-char budget (got $LEN)"; fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
echo "== [S65-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-65.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S65-Z] shebang #!/bin/bash"; else fail "[S65-Z] shebang #!/bin/bash"; fi
for sec in S65-A S65-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S65-Z] [$sec] section header present"; else fail "[S65-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
