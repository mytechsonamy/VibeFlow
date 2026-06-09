#!/bin/bash
# Sprint 53 integration harness — frontend-render-check: actually boots a web UI,
# renders it with mock data, surfaces screenshots, and compares implemented vs
# designed. Ends the "dark tunnel" where a UI ships unit-tested but never
# rendered or compared to the design.
#
# Sections:
#   [S53-A] frontend-render-check skill structure
#   [S53-B] phase-runner TESTING battery wiring (first lane + live front+back note)
#   [S53-C] phase-policy registration + docs
#   [S53-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

FRC="$REPO_ROOT/skills/frontend-render-check/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/FRONTEND-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S53-A] frontend-render-check skill structure =="

assert_file "[S53-A] skills/frontend-render-check/SKILL.md exists" "$FRC"
assert_grep "[S53-A] frontmatter name" "^name: frontend-render-check$" "$FRC"
assert_grep "[S53-A] model-invocable" "^disable-model-invocation: false$" "$FRC"
assert_grep "[S53-A] Phase Contract = TESTING, web UI only" "TESTING\\*\\*, \\*\\*web UI|web UI increments only" "$FRC"
# Boots the app + catches startup bugs.
assert_grep "[S53-A] boots the dev server" "Boot it|boots the dev server|boots the real front-end" "$FRC"
assert_grep "[S53-A] startup failure is a real finding (won't-boot bug)" \
  "fails to start|won't start|path-with-spaces|%20" "$FRC"
assert_grep "[S53-A] detects the framework (vite/next/etc.)" "vite|next|react-scripts" "$FRC"
# Mock data, no backend.
assert_grep "[S53-A] serves mock/fixture data (no live backend)" "mock/fixture|mock data|no backend" "$FRC"
# Capture + SURFACE (anti dark-tunnel).
assert_grep "[S53-A] captures hero-screen screenshots" "screenshot|playwright" "$FRC"
assert_grep "[S53-A] surfaces screenshots to the operator (you SEE it)" \
  "Surface them to the operator|anti-.dark-tunnel|never report .rendered" "$FRC"
assert_grep "[S53-A] names the live localhost URL for Chrome" "http://localhost" "$FRC"
# Design conformance — implemented vs designed.
assert_grep "[S53-A] compares implemented vs designed" "implemented vs designed|Implemented vs Designed|coded screen match the design" "$FRC"
assert_grep "[S53-A] uses design-bridge db_compare_impl for Figma" "db_compare_impl" "$FRC"
assert_grep "[S53-A] side-by-side design.png + impl.png" "<screen>-design.png|side-by-side" "$FRC"
assert_grep "[S53-A] BLOCKED when no relation to the design" "no meaningful relation|no relation to the design" "$FRC"
# Verdict + arm-on-pass + graceful degrade + live-later.
assert_grep "[S53-A] writes frontend-conformance.md" "frontend-conformance.md" "$FRC"
assert_grep "[S53-A] arm-on-pass (Sprint 43)" "only on PASS|only if .VERDICT == .PASS." "$FRC"
assert_grep "[S53-A] graceful-degrade when no headless browser" "Graceful-degrade|no headless browser|do NOT fake it" "$FRC"
assert_grep "[S53-A] notes live front+back is uat-executor/DEPLOYMENT" "uat-executor|live front" "$FRC"

# ---------------------------------------------------------------------------
echo "== [S53-B] phase-runner battery wiring =="

assert_grep "[S53-B] battery includes frontend-render-check" "frontend-render-check" "$RUNNER"
assert_grep "[S53-B] render-check runs first (feeds visual-ai-analyzer)" \
  "Run it \\*\\*first\\*\\*|feed .visual-ai-analyzer|reusing .frontend-render-check" "$RUNNER"
assert_grep "[S53-B] uat-executor noted as the live front+back integration" \
  "live backend|front-end \\+ live backend|front\\+back" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S53-C] phase-policy + docs =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["frontend-render-check"].phases | index("TESTING") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S53-C] phase-policy registers frontend-render-check for TESTING"
  else
    fail "[S53-C] phase-policy registers frontend-render-check for TESTING"
  fi
fi
assert_grep "[S53-C] FRONTEND-TESTING.md documents the render check / dark tunnel" \
  "dark tunnel|frontend-render-check" "$DOC"
assert_grep "[S53-C] docs note mock-now / live-later tiers" "Mock now, live later|mock.*TESTING.*live|live front" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S53-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-53.sh"
assert_grep "[S53-Z] sprint-53.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S53-Z] covers [S53-A]" '\[S53-A\]' "$SELF"
assert_grep "[S53-Z] covers [S53-B]" '\[S53-B\]' "$SELF"
assert_grep "[S53-Z] covers [S53-C]" '\[S53-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
