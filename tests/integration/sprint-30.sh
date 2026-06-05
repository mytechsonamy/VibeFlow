#!/bin/bash
# Sprint 30 integration harness — loop-status dashboard (capstone, B4).
#
# Sections:
#   [S30-A] loop-audit.sh phaseRunner + crossProject sections (reader)
#   [S30-B] /vibeflow:loop-status skill + phase-policy registration
#   [S30-C] docs (LOOP-STATUS.md new, LOOP-AUDIT.md refresh)
#   [S30-Z] harness self-audit

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

LAUDIT="$REPO_ROOT/hooks/scripts/loop-audit.sh"
SKILL="$REPO_ROOT/skills/loop-status/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
LS_DOC="$REPO_ROOT/docs/LOOP-STATUS.md"
LA_DOC="$REPO_ROOT/docs/LOOP-AUDIT.md"

# ---------------------------------------------------------------------------
echo "== [S30-A] loop-audit.sh phaseRunner + crossProject sections =="

assert_file "[S30-A] loop-audit.sh exists" "$LAUDIT"
assert_grep "[S30-A] reads phase-runner-progress.json ledger" "phase-runner-progress\\.json" "$LAUDIT"
assert_grep "[S30-A] derives stepsDone from done steps" 'status==.done.' "$LAUDIT"
assert_grep "[S30-A] emits phaseRunner field" "phaseRunner:" "$LAUDIT"
assert_grep "[S30-A] crossProject gated on globalLearning.enabled" "globalLearning\\.enabled" "$LAUDIT"
assert_grep "[S30-A] reads the global-learning.jsonl store" "global-learning\\.jsonl" "$LAUDIT"
assert_grep "[S30-A] aggregates distinctProjects" "distinctProjects" "$LAUDIT"
assert_grep "[S30-A] computes a cross-project holdRate" "holdRate" "$LAUDIT"
assert_grep "[S30-A] emits crossProject field" "crossProject:" "$LAUDIT"
assert_grep "[S30-A] EMPTY fallback carries phaseRunner+crossProject" '"phaseRunner":null,"crossProject":null' "$LAUDIT"

# Runtime: seed a ledger + a global store; assert the new sections populate.
RT="$(mktemp -d)"; GLOO="$(mktemp -d)"
echo '{"project":"ls","currentPhase":"TESTING","globalLearning":{"enabled":true}}' > "$RT/vibeflow.config.json"
mkdir -p "$RT/.vibeflow/state"
cat > "$RT/.vibeflow/state/phase-runner-progress.json" <<'JSON'
{"phase":"TESTING","status":"running","currentStep":"consensus-round-1","attempt":2,"maxConvergenceAttempts":3,
 "steps":[{"name":"analyzer:coverage-analyzer","status":"done"},{"name":"consensus-round-1","status":"running"}]}
JSON
{
  echo '{"key":"consensus.maxIterations","outcome":"held","phase":"REQUIREMENTS","projectHash":"aaa"}'
  echo '{"key":"consensus.maxIterations","outcome":"held","phase":"REQUIREMENTS","projectHash":"bbb"}'
  echo '{"key":"consensus.maxIterations","outcome":"reverted","phase":"REQUIREMENTS","projectHash":"ccc"}'
} > "$GLOO/global-learning.jsonl"
OUT="$(VIBEFLOW_CWD="$RT" VIBEFLOW_GLOBAL_DIR="$GLOO" bash "$LAUDIT" 2>/dev/null)"
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then pass "[S30-A] runtime: valid JSON"; else fail "[S30-A] runtime: valid JSON"; fi
assert_eq "[S30-A] runtime: phaseRunner.status=running" "running" "$(printf '%s' "$OUT" | jq -r '.phaseRunner.status')"
assert_eq "[S30-A] runtime: phaseRunner.stepsDone=1" "1" "$(printf '%s' "$OUT" | jq -r '.phaseRunner.stepsDone')"
assert_eq "[S30-A] runtime: phaseRunner.stepsTotal=2" "2" "$(printf '%s' "$OUT" | jq -r '.phaseRunner.stepsTotal')"
assert_eq "[S30-A] runtime: phaseRunner.attempt=2" "2" "$(printf '%s' "$OUT" | jq -r '.phaseRunner.attempt')"
assert_eq "[S30-A] runtime: crossProject.distinctProjects=3" "3" "$(printf '%s' "$OUT" | jq -r '.crossProject.distinctProjects')"
assert_eq "[S30-A] runtime: crossProject.holdRate=0.67" "0.67" "$(printf '%s' "$OUT" | jq -r '.crossProject.perKey[] | select(.key=="consensus.maxIterations") | .holdRate')"
assert_eq "[S30-A] runtime: existing autoApply field intact" "0" "$(printf '%s' "$OUT" | jq -r '.autoApply.applied')"
# Fresh project → both sections null.
RT2="$(mktemp -d)"; echo '{"project":"x","currentPhase":"REQUIREMENTS"}' > "$RT2/vibeflow.config.json"
OUT2="$(VIBEFLOW_CWD="$RT2" bash "$LAUDIT" 2>/dev/null)"
assert_eq "[S30-A] runtime: fresh phaseRunner=null" "null" "$(printf '%s' "$OUT2" | jq -r '.phaseRunner')"
assert_eq "[S30-A] runtime: fresh crossProject=null" "null" "$(printf '%s' "$OUT2" | jq -r '.crossProject')"
# globalLearning OFF → crossProject null even with a store.
OUT3="$(VIBEFLOW_CWD="$RT2" VIBEFLOW_GLOBAL_DIR="$GLOO" bash "$LAUDIT" 2>/dev/null)"
assert_eq "[S30-A] runtime: store present but globalLearning off → null" "null" "$(printf '%s' "$OUT3" | jq -r '.crossProject')"
rm -rf "$RT" "$RT2" "$GLOO"

# ---------------------------------------------------------------------------
echo "== [S30-B] /vibeflow:loop-status skill =="

assert_file "[S30-B] skills/loop-status/SKILL.md exists" "$SKILL"
assert_grep "[S30-B] frontmatter name: loop-status" "^name: loop-status" "$SKILL"
assert_grep "[S30-B] frontmatter has a description" "^description:" "$SKILL"
assert_grep "[S30-B] runs loop-audit.sh" "loop-audit\\.sh" "$SKILL"
assert_grep "[S30-B] renders phase-runner line" "Phase-runner" "$SKILL"
assert_grep "[S30-B] renders auto-apply tally" "Auto-apply" "$SKILL"
assert_grep "[S30-B] renders cooled-down keys" "Cooled-down|cooled-down" "$SKILL"
assert_grep "[S30-B] renders armed watch" "Armed watch|armedWatch" "$SKILL"
assert_grep "[S30-B] renders learning findings" "Learning|findingCount" "$SKILL"
assert_grep "[S30-B] renders cross-project recommendation" "Cross-project|crossProject" "$SKILL"
assert_grep "[S30-B] flags revertRate >= 0.5" "revertRate" "$SKILL"
assert_grep "[S30-B] cross-project is recommendation-only" "recommendation only|does NOT auto-allowlist" "$SKILL"
assert_grep "[S30-B] writes .vibeflow/reports/loop-status.md" "\\.vibeflow/reports/loop-status\\.md" "$SKILL"
assert_grep "[S30-B] idle collapse path" "idle" "$SKILL"
assert_grep "[S30-B] declares read-only" "[Rr]ead-only" "$SKILL"
# Read-only: the only Write target is the report (no Write to config/source).
if grep -qE "Write" "$SKILL" && ! grep -qE "Write.*vibeflow\\.config\\.json|Edit.*autoApply" "$SKILL"; then
  pass "[S30-B] read-only: no Write/Edit to config or autoApply.keys"
else fail "[S30-B] read-only: no Write/Edit to config or autoApply.keys"; fi
# Phase-policy registration.
if jq -e '.skills["loop-status"]' "$POLICY" >/dev/null 2>&1; then pass "[S30-B] registered in phase-policy.json"; else fail "[S30-B] registered in phase-policy.json"; fi
assert_eq "[S30-B] phase-policy phases=ALL" "ALL" "$(jq -r '.skills["loop-status"].phases' "$POLICY")"
assert_grep "[S30-B] phase-policy description mentions read-only" "[Rr]ead-only" <(jq -r '.skills["loop-status"].description' "$POLICY")

# ---------------------------------------------------------------------------
echo "== [S30-C] docs =="

assert_file "[S30-C] docs/LOOP-STATUS.md exists" "$LS_DOC"
assert_grep "[S30-C] doc: two-surfaces contrast with /vibeflow:flow-status" "/vibeflow:flow-status" "$LS_DOC"
assert_grep "[S30-C] doc: the dashboard layout" "Autonomous Loop" "$LS_DOC"
assert_grep "[S30-C] doc: phase-runner line documented" "Phase-runner" "$LS_DOC"
assert_grep "[S30-C] doc: revertRate >= 0.5 flag" "revertRate" "$LS_DOC"
assert_grep "[S30-C] doc: cross-project is recommendation-only" "recommendation only" "$LS_DOC"
assert_grep "[S30-C] doc: idle collapse" "idle" "$LS_DOC"
assert_grep "[S30-C] doc: the written report" "\\.vibeflow/reports/loop-status\\.md" "$LS_DOC"
assert_grep "[S30-C] doc: read-only guarantee" "[Rr]ead-only" "$LS_DOC"
assert_grep "[S30-C] LOOP-AUDIT.md mentions phaseRunner section" "phaseRunner" "$LA_DOC"
assert_grep "[S30-C] LOOP-AUDIT.md mentions crossProject section" "crossProject" "$LA_DOC"
assert_grep "[S30-C] LOOP-AUDIT.md links to LOOP-STATUS.md" "LOOP-STATUS\\.md" "$LA_DOC"

# ---------------------------------------------------------------------------
echo "== [S30-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-30.sh"
if [[ -x "$SELF" ]]; then pass "[S30-Z] sprint-30.sh is executable"; else fail "[S30-Z] sprint-30.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S30-Z] sprint-30.sh shebang is #!/bin/bash"
else fail "[S30-Z] sprint-30.sh shebang is #!/bin/bash"; fi
for sec in S30-A S30-B S30-C S30-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S30-Z] [$sec] section header present"
  else fail "[S30-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
