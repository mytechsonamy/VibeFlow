#!/bin/bash
# Sprint 44 integration harness — input-validation-matrix skill + the
# UI-conditional front-end battery wired into the phase-runner TESTING walk.
#
# Sections:
#   [S44-A] input-validation-matrix skill structure
#   [S44-B] phase-runner TESTING UI-conditional front-end battery
#   [S44-C] phase-policy registration + docs/FRONTEND-TESTING.md
#   [S44-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

IVM="$REPO_ROOT/skills/input-validation-matrix/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/FRONTEND-TESTING.md"

# ---------------------------------------------------------------------------
echo "== [S44-A] input-validation-matrix skill structure =="

assert_file "[S44-A] skills/input-validation-matrix/SKILL.md exists" "$IVM"
assert_grep "[S44-A] frontmatter name" "^name: input-validation-matrix$" "$IVM"
assert_grep "[S44-A] model-invocable" "^disable-model-invocation: false$" "$IVM"
assert_grep "[S44-A] Phase Contract = TESTING" "Runs in \\*\\*TESTING\\*\\*" "$IVM"
assert_grep "[S44-A] UI-only guard (skips backend/infra)" "backend.*infra|no UI inputs in this increment" "$IVM"
assert_grep "[S44-A] field inventory from design + requirements + source" \
  "Design spec|Requirements|Source" "$IVM"
# Every validation category present.
assert_grep "[S44-A] required/presence category" "Required / presence" "$IVM"
assert_grep "[S44-A] type category (numeric vs alphanumeric)" "Type.*wrong type|numeric / integer" "$IVM"
assert_grep "[S44-A] boundary category (value + length)" "Boundary .value.|Boundary .length." "$IVM"
assert_grep "[S44-A] format category" "Format.*malformed|wrong IBAN" "$IVM"
assert_grep "[S44-A] injection/safety category" "Injection / safety|OR 1=1|script.alert" "$IVM"
assert_grep "[S44-A] output-control (formatting/masking)" "Output control|masking" "$IVM"
assert_grep "[S44-A] cross-field rules" "Cross-field" "$IVM"
assert_grep "[S44-A] writes tests INTO the project suite (enforced gate)" \
  "into the real suite|alongside the project's existing tests|enforced gate" "$IVM"
assert_grep "[S44-A] writes validation-matrix.md" "validation-matrix.md" "$IVM"
assert_grep "[S44-A] arm-on-pass (Sprint 43)" "only on PASS|only if .VERDICT == .PASS." "$IVM"

# ---------------------------------------------------------------------------
echo "== [S44-B] phase-runner TESTING UI-conditional battery =="

assert_grep "[S44-B] phase-runner has a TESTING front-end battery section" \
  "front-end battery" "$RUNNER"
assert_grep "[S44-B] battery is UI-conditional (ui/mixed)" \
  "UI-facing|classification.*ui|design-spec.md exists" "$RUNNER"
assert_grep "[S44-B] backend increment skips the battery" \
  "backend/infra increment skips|skips the battery" "$RUNNER"
assert_grep "[S44-B] battery includes input-validation-matrix" "input-validation-matrix" "$RUNNER"
assert_grep "[S44-B] battery includes e2e + visual + business-rule + traceability + uat" \
  "e2e-test-writer" "$RUNNER"
assert_grep "[S44-B] battery includes visual-ai-analyzer (design conformance)" "visual-ai-analyzer" "$RUNNER"
assert_grep "[S44-B] battery includes traceability + business-rule + uat" \
  "traceability-engine" "$RUNNER"
assert_grep "[S44-B] runs them as Skills (not general agents)" \
  "as a \\*\\*Skill\\*\\*|each as a \\*\\*Skill\\*\\*" "$RUNNER"
assert_grep "[S44-B] tests written into the suite → existing gates enforce" \
  "into the project suite|gated test suite|existing gates enforce" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S44-C] phase-policy + docs =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["input-validation-matrix"].phases | index("TESTING") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S44-C] phase-policy registers input-validation-matrix for TESTING"
  else
    fail "[S44-C] phase-policy registers input-validation-matrix for TESTING"
  fi
fi
assert_file "[S44-C] docs/FRONTEND-TESTING.md exists" "$DOC"
assert_grep "[S44-C] docs map concerns to skills" "validation|visual-ai-analyzer|e2e-test-writer" "$DOC"
assert_grep "[S44-C] docs explain it's a gate not a side report" "gate, not a side report|enforce them|guarantee" "$DOC"
assert_grep "[S44-C] docs note A/B is out of scope (production experiment)" "A/B|production experiment" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S44-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-44.sh"
assert_grep "[S44-Z] sprint-44.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S44-Z] covers [S44-A]" '\[S44-A\]' "$SELF"
assert_grep "[S44-Z] covers [S44-B]" '\[S44-B\]' "$SELF"
assert_grep "[S44-Z] covers [S44-C]" '\[S44-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
