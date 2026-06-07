#!/bin/bash
# Sprint 35 integration harness — design-bootstrap: UI-classification, the
# compare-both option, and the technical-design path.
#
# Sections:
#   [S35-A] Step 1b UI-facing classification (backend-increment flag)
#   [S35-B] option 4 — Both (compare Claude-native vs Figma)
#   [S35-C] option 5 — Technical design (low/no-UI increment)
#   [S35-Z] harness self-audit

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
echo "== [S35-A] Step 1b — UI-facing classification =="

assert_grep "[S35-A] has a Step 1b UI-facing classification" \
  "Step 1b|UI-facing\?|Is this increment UI-facing" "$DB"
assert_grep "[S35-A] distinguishes UI signals vs backend signals" \
  "UI signals|Backend signals" "$DB"
assert_grep "[S35-A] flags backend/infra increments" \
  "backend.?/.?infra|backend/infra-heavy|backend signals dominate" "$DB"
assert_grep "[S35-A] notes heavy technical design belongs in ARCHITECTURE" \
  "ARCHITECTURE phase|belongs in the \\*\\*ARCHITECTURE|hand the heavy parts to ARCHITECTURE" "$DB"
assert_grep "[S35-A] still asks (never auto-decides)" \
  "you still \\*\\*ask\\*\\*|never auto-decide|Do \\*\\*not\\*\\* assume a default" "$DB"

# ---------------------------------------------------------------------------
echo "== [S35-B] option 4 — Both (compare) =="

assert_grep "[S35-B] menu offers option 4 Both (compare)" \
  "4\\. Both \\(compare\\)|Both \\(compare" "$DB"
assert_grep "[S35-B] has a 3·D compare route" "### 3·D" "$DB"
assert_grep "[S35-B] produces both candidates under design/candidates" \
  "design/candidates" "$DB"
assert_grep "[S35-B] writes a side-by-side design-comparison.md" \
  "design/design-comparison.md|design-comparison.md" "$DB"
assert_grep "[S35-B] operator picks the one to carry forward" \
  "pick the one|Ask the operator to pick|carry forward" "$DB"
assert_grep "[S35-B] chosen candidate becomes the canonical design-spec.md" \
  "canonical .*design/design-spec.md|to the canonical" "$DB"
assert_grep "[S35-B] can use db_compare_impl on screenshots" \
  "db_compare_impl" "$DB"
assert_grep "[S35-B] allowed-tools include cp (copy the chosen candidate)" \
  "Bash\\(cp \\*\\)" "$DB"

# ---------------------------------------------------------------------------
echo "== [S35-C] option 5 — Technical design =="

assert_grep "[S35-C] menu offers option 5 Technical design" \
  "5\\. Technical design|Technical design—|Technical design " "$DB"
assert_grep "[S35-C] has a 3·E technical-design route" "### 3·E" "$DB"
assert_grep "[S35-C] writes design-spec.md as a TECHNICAL design" \
  "TECHNICAL design" "$DB"
assert_grep "[S35-C] recommends ARCHITECTURE for heavy architecture" \
  "recommend doing it in the \\*\\*ARCHITECTURE|ARCHITECTURE.* phase .*ADR|ARCHITECTURE phase" "$DB"
assert_grep "[S35-C] no tokens/wireframes when there is no UI" \
  "No .design-tokens.json|there's no UI|no UI" "$DB"

# Docs cover the two new options.
assert_grep "[S35-C] DESIGN-PHASE.md documents Both (compare)" "Both \\(compare\\)" "$DOC"
assert_grep "[S35-C] DESIGN-PHASE.md documents Technical design" "Technical design" "$DOC"
assert_grep "[S35-C] DESIGN-PHASE.md notes the backend-increment classification" \
  "classifies the increment|backend/infra-heavy" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S35-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-35.sh"
assert_grep "[S35-Z] sprint-35.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S35-Z] covers [S35-A]" '\[S35-A\]' "$SELF"
assert_grep "[S35-Z] covers [S35-B]" '\[S35-B\]' "$SELF"
assert_grep "[S35-Z] covers [S35-C]" '\[S35-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
