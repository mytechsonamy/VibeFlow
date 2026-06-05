#!/bin/bash
# Sprint 29 integration harness — phase-runner TESTING auto-run (B5).
#
# Sections:
#   [S29-A] TESTING generate-artifacts pre-step
#   [S29-B] best-effort + --no-generate opt-out + TESTING-only guard
#   [S29-C] Docs (TESTING-READINESS.md refresh)
#   [S29-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
TR="$REPO_ROOT/docs/TESTING-READINESS.md"

# ---------------------------------------------------------------------------
echo "== [S29-A] TESTING generate-artifacts pre-step =="

assert_grep "[S29-A] Step 2a generate-artifacts (TESTING only)" "Step 2a|Generate TESTING artifacts" "$PR"
assert_grep "[S29-A] gated on CURRENT == TESTING" 'CURRENT.* == .TESTING|"\$CURRENT" == "TESTING"' "$PR"
assert_grep "[S29-A] resolves tech.coverageCommand" "tech\\.coverageCommand" "$PR"
assert_grep "[S29-A] reads tech.testRunner for the default" "tech\\.testRunner" "$PR"
assert_grep "[S29-A] vitest default --coverage" "npx vitest run --coverage" "$PR"
assert_grep "[S29-A] jest default --coverage" "npx jest --coverage" "$PR"
assert_grep "[S29-A] pytest default --cov" "pytest --cov" "$PR"
assert_grep "[S29-A] dotnet default coverage collect" "dotnet test --collect" "$PR"
assert_grep "[S29-A] writes a generate:coverage ledger step" "generate:coverage" "$PR"
assert_grep "[S29-A] allowed-tools include npx/npm runners" "Bash\\(npx \\*\\)|Bash\\(npm \\*\\)" "$PR"
assert_grep "[S29-A] allowed-tools include pytest/dotnet runners" "Bash\\(pytest \\*\\)|Bash\\(dotnet \\*\\)" "$PR"

# Runtime: the coverage-command resolution defaulting.
_resolve() { # <testRunner> <override>
  local RUNNER="$1" COV_CMD="$2"
  if [[ -z "$COV_CMD" ]]; then
    case "$RUNNER" in
      vitest) COV_CMD='npx vitest run --coverage' ;;
      jest)   COV_CMD='npx jest --coverage' ;;
      pytest) COV_CMD='pytest --cov --cov-report=json' ;;
      dotnet) COV_CMD='dotnet test --collect:"XPlat Code Coverage"' ;;
      *)      COV_CMD='' ;;
    esac
  fi
  printf '%s' "$COV_CMD"
}
assert_eq "[S29-A] runtime: vitest → npx vitest run --coverage" "npx vitest run --coverage" "$(_resolve vitest '')"
assert_eq "[S29-A] runtime: pytest → pytest --cov --cov-report=json" "pytest --cov --cov-report=json" "$(_resolve pytest '')"
assert_eq "[S29-A] runtime: unknown runner → empty (skip)" "" "$(_resolve rustcargo '')"
assert_eq "[S29-A] runtime: explicit override wins" "make cov" "$(_resolve vitest 'make cov')"

# ---------------------------------------------------------------------------
echo "== [S29-B] best-effort + opt-out + TESTING-only guard =="

assert_grep "[S29-B] best-effort: continue on coverage-command failure" "continuing — analyzer will surface|do NOT abort|continuing" "$PR"
assert_grep "[S29-B] --no-generate flag documented" "\\-\\-no-generate" "$PR"
assert_grep "[S29-B] VF_SKIP_GENERATE env opt-out" "VF_SKIP_GENERATE" "$PR"
assert_grep "[S29-B] NO_GENERATE resolved from flag/env" "NO_GENERATE" "$PR"
assert_grep "[S29-B] guard: only runs in TESTING" "TESTING only|Other phases skip|only.*TESTING" "$PR"
assert_grep "[S29-B] unknown runner → skipped ledger note" "skipped|no coverage command" "$PR"

# ---------------------------------------------------------------------------
echo "== [S29-C] docs =="

assert_file "[S29-C] docs/TESTING-READINESS.md exists" "$TR"
assert_grep "[S29-C] doc: TESTING is a one-command walk" "one-command walk|one command" "$TR"
assert_grep "[S29-C] doc: generates coverage first" "generates the coverage artifact|generate" "$TR"
assert_grep "[S29-C] doc: per-runner default table" "npx vitest run --coverage" "$TR"
assert_grep "[S29-C] doc: tech.coverageCommand override" "tech\\.coverageCommand" "$TR"
assert_grep "[S29-C] doc: --no-generate opt-out" "\\-\\-no-generate|VF_SKIP_GENERATE" "$TR"
assert_grep "[S29-C] doc: best-effort surfaces the gap" "best-effort|continues|missing-coverage" "$TR"

# ---------------------------------------------------------------------------
echo "== [S29-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-29.sh"
if [[ -x "$SELF" ]]; then pass "[S29-Z] sprint-29.sh is executable"; else fail "[S29-Z] sprint-29.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S29-Z] sprint-29.sh shebang is #!/bin/bash"
else fail "[S29-Z] sprint-29.sh shebang is #!/bin/bash"; fi
for sec in S29-A S29-B S29-C S29-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S29-Z] [$sec] section header present"
  else fail "[S29-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
