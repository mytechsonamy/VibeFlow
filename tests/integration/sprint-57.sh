#!/bin/bash
# Sprint 57 integration harness — UI scenario enumeration in PLANNING.
# test-strategy-planner produced per-requirement happy/edge/negative scenarios
# but never enumerated the UI surface up front (per-field visual conformance,
# per-field validation, backend-data binding). Those got generated only in
# TESTING, so they were never part of the AI-reviewed PLANNING deliverable and
# the front-end battery had nothing concrete to implement against. Sprint 57
# adds a UI-conditional Step 2b (platform web/all + design-spec exists) that
# enumerates visual / validation / data-binding scenarios per hero screen/field,
# RTM-traced, and names the TESTING front-end battery that implements them.
#
# Sections:
#   [S57-A] Step 2b UI scenario enumeration (conditional + 3 dimensions)
#   [S57-B] scenario-set.md + RTM carry the UI block + FR→screen→UI chain
#   [S57-C] downstream front-end battery + coverage-gap UI categories
#   [S57-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

TSP="$REPO_ROOT/skills/test-strategy-planner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S57-A] Step 2b UI scenario enumeration =="

assert_grep "[S57-A] has a Step 2b UI Scenario Enumeration heading" \
  "Step 2b: UI Scenario Enumeration" "$TSP"
assert_grep "[S57-A] is UI-conditional on platform web/all" \
  "Platform is .web. or .all." "$TSP"
assert_grep "[S57-A] is UI-conditional on a design spec existing" \
  "design/design-spec.md" "$TSP"
assert_grep "[S57-A] skips + records for non-UI increments" \
  "skip this step|skipped . non-UI increment" "$TSP"
assert_grep "[S57-A] enumerates per hero screen AND each field/control" \
  "for each hero screen and each" "$TSP"
assert_grep "[S57-A] visual-conformance dimension" \
  "SCN-UI-<screen>-V-NN" "$TSP"
assert_grep "[S57-A] field-validation dimension" \
  "SCN-UI-<screen>-VAL-NN" "$TSP"
assert_grep "[S57-A] backend-data-binding dimension" \
  "SCN-UI-<screen>-DATA-NN" "$TSP"
assert_grep "[S57-A] visual dimension covers states (default/hover/focus/disabled/error/loading)" \
  "default / hover / focus / disabled / error / loading" "$TSP"
assert_grep "[S57-A] data dimension covers loading/empty/error/offline states" \
  "loading, populated, empty, error, offline" "$TSP"
assert_grep "[S57-A] validation dimension covers required/type/boundary/format" \
  "required, type, min/max boundary, format" "$TSP"
assert_grep "[S57-A] Glob used to detect the design spec" \
  "Glob" "$TSP"

# ---------------------------------------------------------------------------
echo "== [S57-B] scenario-set.md + RTM carry UI block & chain =="

assert_grep "[S57-B] scenario-set example has a UI Scenarios block" \
  "## UI Scenarios" "$TSP"
assert_grep "[S57-B] UI block uses '### UI: <screen> (serves: FR-...)' form" \
  "UI: LoginScreen .*serves: FR-001" "$TSP"
assert_grep "[S57-B] metadata line counts UI scenarios" \
  "UI scenarios: XX" "$TSP"
assert_grep "[S57-B] RTM example carries the FR→screen→UI chain" \
  "User login \(UI: LoginScreen\)" "$TSP"
assert_grep "[S57-B] RTM must carry FR→screen→UI scenario chain (prose)" \
  "FR-\* . screen . UI" "$TSP"
assert_grep "[S57-B] UI scenarios traced back to functional requirement(s)" \
  "Trace every UI scenario back to the functional requirement" "$TSP"

# ---------------------------------------------------------------------------
echo "== [S57-C] downstream battery + coverage-gap UI categories =="

assert_grep "[S57-C] names frontend-render-check as implementer" \
  "frontend-render-check" "$TSP"
assert_grep "[S57-C] names input-validation-matrix as implementer" \
  "input-validation-matrix" "$TSP"
assert_grep "[S57-C] names visual-ai-analyzer as implementer" \
  "visual-ai-analyzer" "$TSP"
assert_grep "[S57-C] names uat-executor as implementer" \
  "uat-executor" "$TSP"
assert_grep "[S57-C] coverage gap adds UI_UNTESTED" \
  "UI_UNTESTED" "$TSP"
assert_grep "[S57-C] coverage gap adds UI_DATA_GAP" \
  "UI_DATA_GAP" "$TSP"
assert_grep "[S57-C] coverage gap adds DESIGN_REQ_GAP" \
  "DESIGN_REQ_GAP" "$TSP"
# A screen with no backing requirement is a finding, not a silent add.
assert_grep "[S57-C] does not invent a requirement to cover a stray screen" \
  "do not invent a requirement" "$TSP"

# allowed-tools must include Glob (used by the design-spec detection).
assert_grep "[S57-C] allowed-tools includes Glob" \
  "^allowed-tools:.*Glob" "$TSP"

# ---------------------------------------------------------------------------
echo "== [S57-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-57.sh"
assert_grep "[S57-Z] sprint-57.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S57-Z] covers [S57-A]" '\[S57-A\]' "$SELF"
assert_grep "[S57-Z] covers [S57-B]" '\[S57-B\]' "$SELF"
assert_grep "[S57-Z] covers [S57-C]" '\[S57-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
