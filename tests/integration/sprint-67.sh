#!/bin/bash
# Sprint 67 integration harness — DEVELOPMENT-phase render-as-you-build. The
# visual render check now runs in DEVELOPMENT (scoped to the screens the increment
# changed), so every new screen is rendered + visually checked while it's built,
# not deferred to TESTING — the gap that let Clera's visual defects ship.
#
# Sections:
#   [S67-A] frontend-render-check runs in DEVELOPMENT + arm-on-pass is TESTING-only
#   [S67-B] phase-policy: frontend-render-check phases include DEVELOPMENT
#   [S67-C] phase-runner DEVELOPMENT runs frontend-render-check (proportionate gate)
#   [S67-D] docs
#   [S67-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

FRC="$REPO_ROOT/skills/frontend-render-check/SKILL.md"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/FRONTEND-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S67-A] frontend-render-check DEVELOPMENT render-as-you-build =="

assert_grep "[S67-A] Phase Contract runs in DEVELOPMENT + TESTING" "Runs in \\*\\*DEVELOPMENT\\*\\* \\(render-as-you-build\\) \\*\\*and TESTING\\*\\*" "$FRC"
assert_grep "[S67-A] DEVELOPMENT mode scopes to changed screens" "screens this increment built/changed" "$FRC"
assert_grep "[S67-A] DEVELOPMENT is a proportionate gate (BLOCKED stops)" "proportionate gate" "$FRC"
assert_grep "[S67-A] DEVELOPMENT does NOT arm the marker" "NOT arm the consensus marker in DEVELOPMENT" "$FRC"
assert_grep "[S67-A] arm-on-pass Final Step is TESTING-only" "current phase is TESTING AND .VERDICT" "$FRC"
assert_grep "[S67-A] never arm in DEVELOPMENT regardless of verdict" "never arm" "$FRC"

# ---------------------------------------------------------------------------
echo "== [S67-B] phase-policy registration =="

if jq -e '.skills["frontend-render-check"].phases | index("DEVELOPMENT")' "$POLICY" >/dev/null 2>&1; then
  pass "[S67-B] frontend-render-check phases include DEVELOPMENT"
else
  fail "[S67-B] frontend-render-check phases include DEVELOPMENT"
fi
if jq -e '.skills["frontend-render-check"].phases | index("TESTING")' "$POLICY" >/dev/null 2>&1; then
  pass "[S67-B] frontend-render-check still includes TESTING"
else
  fail "[S67-B] frontend-render-check still includes TESTING"
fi

# ---------------------------------------------------------------------------
echo "== [S67-C] phase-runner DEVELOPMENT render step =="

assert_grep "[S67-C] DEVELOPMENT render-as-you-build section" "render every new screen as it.s built" "$PR"
assert_grep "[S67-C] gated on UI-facing (vf_web_ui_kind ≠ none)" "vf_web_ui_kind" "$PR"
assert_grep "[S67-C] runs frontend-render-check via the Skill tool" "Skill: vibeflow:frontend-render-check" "$PR"
assert_grep "[S67-C] BLOCKED stops (proportionate gate)" "proportionate DEVELOPMENT gate" "$PR"
assert_grep "[S67-C] drift surfaces + continue" "surface \\*\\*prominently\\*\\*" "$PR"
assert_grep "[S67-C] never arms the marker in DEVELOPMENT" "never arms the consensus marker" "$PR"

# ---------------------------------------------------------------------------
echo "== [S67-D] docs =="

assert_grep "[S67-D] FRONTEND-TESTING documents render-as-you-build" "[Rr]ender-as-you-build in DEVELOPMENT" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S67-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-67.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S67-Z] shebang #!/bin/bash"; else fail "[S67-Z] shebang #!/bin/bash"; fi
for sec in S67-A S67-B S67-C S67-D S67-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S67-Z] [$sec] section header present"; else fail "[S67-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
