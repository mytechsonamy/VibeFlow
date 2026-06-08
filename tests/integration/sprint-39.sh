#!/bin/bash
# Sprint 39 integration harness — brownfield-intake (the brownfield on-ramp).
#
# Sections:
#   [S39-A] brownfield-intake skill structure (fingerprint + 4 intake paths)
#   [S39-B] phase-policy registration + onboard brownfield breadcrumb
#   [S39-C] docs/BROWNFIELD.md
#   [S39-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

BI="$REPO_ROOT/skills/brownfield-intake/SKILL.md"
ONB="$REPO_ROOT/skills/onboard/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
DOC="$REPO_ROOT/docs/BROWNFIELD.md"

# ---------------------------------------------------------------------------
echo "== [S39-A] brownfield-intake skill structure =="

assert_file "[S39-A] skills/brownfield-intake/SKILL.md exists" "$BI"
assert_grep "[S39-A] frontmatter name: brownfield-intake" "^name: brownfield-intake$" "$BI"
assert_grep "[S39-A] model-invocable" "^disable-model-invocation: false$" "$BI"
assert_grep "[S39-A] Phase Contract restricts to REQUIREMENTS" "## Phase Contract" "$BI"
assert_grep "[S39-A] REQUIREMENTS-only guard" "REQUIREMENTS.*only|in \\*\\*REQUIREMENTS\\*\\* only" "$BI"
# Fingerprints the codebase first (codebase-intel).
assert_grep "[S39-A] uses ci_analyze_structure" "ci_analyze_structure" "$BI"
assert_grep "[S39-A] uses ci_dependency_graph" "ci_dependency_graph" "$BI"
assert_grep "[S39-A] uses ci_find_hotspots" "ci_find_hotspots" "$BI"
assert_grep "[S39-A] uses ci_tech_debt_scan" "ci_tech_debt_scan" "$BI"
assert_grep "[S39-A] reuses/writes the codebase fingerprint" "codebase-fingerprint.md" "$BI"
# The 4 intake paths.
assert_grep "[S39-A] path 1 — Describe it (plain language)" "Describe it" "$BI"
assert_grep "[S39-A] path 2 — Point to a doc" "Point to a doc" "$BI"
assert_grep "[S39-A] path 3 — Guided Q&A" "Guided Q&A|Guided Q.A" "$BI"
assert_grep "[S39-A] path 4 — From an issue (gh/glab)" "From an issue|gh issue view|glab issue" "$BI"
assert_grep "[S39-A] allowed-tools include gh + glab for the issue path" \
  "Bash\\(gh \\*\\).*Bash\\(glab \\*\\)|Bash\\(glab \\*\\)" "$BI"
# Output: code-anchored, increment-scoped requirements doc + classification.
assert_grep "[S39-A] writes a scoped requirements doc" "<increment-slug>-requirements.md|increment.*requirements" "$BI"
assert_grep "[S39-A] anchors the increment to the code (modules touched)" "Code anchor|modules / files|dependency graph" "$BI"
assert_grep "[S39-A] classifies the change type (UI/backend/infra)" "Change-type classification|UI / backend / infra" "$BI"
assert_grep "[S39-A] notes phase implications of the classification" "phase implications|DESIGN.*light|routes the later phases" "$BI"
assert_grep "[S39-A] breadcrumbs to prd-quality-analyzer" "▶ Next: /vibeflow:prd-quality-analyzer" "$BI"

# ---------------------------------------------------------------------------
echo "== [S39-B] phase-policy + onboard wiring =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["brownfield-intake"].phases | index("REQUIREMENTS") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S39-B] phase-policy registers brownfield-intake for REQUIREMENTS"
  else
    fail "[S39-B] phase-policy registers brownfield-intake for REQUIREMENTS"
  fi
fi
assert_grep "[S39-B] onboard branches greenfield vs brownfield at hand-off" \
  "greenfield vs brownfield|Brownfield.*source files already exist" "$ONB"
assert_grep "[S39-B] onboard brownfield breadcrumb → brownfield-intake" \
  "▶ Next: /vibeflow:brownfield-intake" "$ONB"
assert_grep "[S39-B] onboard greenfield breadcrumb still → prd-quality-analyzer" \
  "▶ Next: /vibeflow:prd-quality-analyzer" "$ONB"

# ---------------------------------------------------------------------------
echo "== [S39-C] docs/BROWNFIELD.md =="

assert_file "[S39-C] docs/BROWNFIELD.md exists" "$DOC"
assert_grep "[S39-C] documents the on-ramp flow (onboard → brownfield-intake)" \
  "brownfield-intake" "$DOC"
assert_grep "[S39-C] documents the 4 intake paths" "Describe it|Point to a doc|Guided Q&A|From an issue" "$DOC"
assert_grep "[S39-C] explains increment-scoped (not whole-product)" "increment|not the whole product|scoped" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S39-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-39.sh"
assert_grep "[S39-Z] sprint-39.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S39-Z] covers [S39-A]" '\[S39-A\]' "$SELF"
assert_grep "[S39-Z] covers [S39-B]" '\[S39-B\]' "$SELF"
assert_grep "[S39-Z] covers [S39-C]" '\[S39-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
