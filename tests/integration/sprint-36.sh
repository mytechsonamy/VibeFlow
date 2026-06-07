#!/bin/bash
# Sprint 36 integration harness — design-bootstrap fair-fidelity rendering:
# the compare-both Claude candidate renders HTML/CSS mockups so the comparison
# against Figma's .png exports is rendered-vs-rendered (not wireframe-vs-image).
#
# Sections:
#   [S36-A] compare-both renders the Claude candidate (HTML mockups → fair compare)
#   [S36-B] Claude-native path emits a rendered visual + the "merge" explainer
#   [S36-C] docs/DESIGN-PHASE.md explains rendered-vs-rendered
#   [S36-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

DB="$REPO_ROOT/skills/design-bootstrap/SKILL.md"
DOC="$REPO_ROOT/docs/DESIGN-PHASE.md"

# ---------------------------------------------------------------------------
echo "== [S36-A] compare-both renders the Claude candidate =="

assert_grep "[S36-A] 3·D notes wireframe-vs-png is an unfair comparison" \
  "unfair comparison|always .looks nicer|not because the design is" "$DB"
assert_grep "[S36-A] Claude candidate emits self-contained HTML/CSS mockups" \
  "self-contained HTML/CSS mockups|HTML/CSS mockups" "$DB"
assert_grep "[S36-A] hero-screen mockups under candidates/claude-native/mockups" \
  "design/candidates/claude-native/mockups" "$DB"
assert_grep "[S36-A] mockups are token-driven (inline CSS from design-tokens.json)" \
  "inline CSS driven by .design-tokens.json|CSS driven by" "$DB"
assert_grep "[S36-A] optional screenshot to .png when a tool is available" \
  "screenshot tool is available|capture each mockup to|\.png so the comparison" "$DB"
assert_grep "[S36-A] comparison is visual-vs-visual (rendered-vs-rendered)" \
  "visual-vs-visual|rendered-vs-rendered|two .*rendered. designs" "$DB"
assert_grep "[S36-A] Sprint 36 marker present in 3·D" "Sprint 36" "$DB"

# ---------------------------------------------------------------------------
echo "== [S36-B] Claude-native rendered visual + merge explainer =="

assert_grep "[S36-B] 3·A prefers a rendered HTML mockup per hero screen" \
  "rendered visual|HTML/CSS mockup per hero screen|design/mockups/<screen>.html" "$DB"
assert_grep "[S36-B] explains a wireframe reads low-fidelity even when strong" \
  "low-fidelity even when|reads as low-fidelity|wireframe alone" "$DB"
# The "what merge means" explainer (operators were confused by it).
assert_grep "[S36-B] documents what 'merge' means" \
  'What .merge. means|"merge" = keep both|keep both, each in its' "$DB"
assert_grep "[S36-B] merge = same design, nothing to reconcile" \
  "same\\*\\* design|nothing conflicting to reconcile|nothing to reconcile" "$DB"

# ---------------------------------------------------------------------------
echo "== [S36-C] docs explain rendered-vs-rendered =="

assert_grep "[S36-C] DESIGN-PHASE.md mentions a rendered HTML/CSS mockup" \
  "rendered HTML/CSS mockup|design/mockups/<screen>.html" "$DOC"
assert_grep "[S36-C] DESIGN-PHASE.md explains the fair (rendered-vs-rendered) compare" \
  "rendered-vs-rendered|not rendered|fair call" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S36-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-36.sh"
assert_grep "[S36-Z] sprint-36.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S36-Z] covers [S36-A]" '\[S36-A\]' "$SELF"
assert_grep "[S36-Z] covers [S36-B]" '\[S36-B\]' "$SELF"
assert_grep "[S36-Z] covers [S36-C]" '\[S36-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
