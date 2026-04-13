#!/bin/bash
# VibeFlow Sprint 3 integration harness.
#
# Complements tests/integration/run.sh (platform-wide baseline) and
# tests/integration/sprint-2.sh (Sprint 2 deliverables). This harness
# proves the Sprint 3 deliverables hang together as a coherent
# pipeline:
#
#   - the 15 Sprint-3 skills (L1/L2/L3) exist in the expected shape
#   - each skill declares its io-standard primary output
#   - cross-skill wiring is coherent (uat → analyzer, regression →
#     priority, reconciliation → release, etc.)
#   - every gating skill declares its gate contract string
#   - dev-ops and observability MCP servers still respond
#   - orchestrator.md declares all 7 PIPELINE-N flows
#
# This harness does NOT duplicate run.sh's canonical-invariant or
# gate-contract-sentinel checks. Run both from CI; order is not
# significant.
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
IO_STANDARD="$SKILLS_DIR/_standards/io-standard.md"
ORCH="$SKILLS_DIR/_standards/orchestrator.md"
DO_DIST="$REPO_ROOT/mcp-servers/dev-ops/dist/index.js"
OB_DIST="$REPO_ROOT/mcp-servers/observability/dist/index.js"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$expected" == "$actual" ]] && pass "$label" \
    || fail "$label (expected=$expected actual=$actual)"
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  [[ "$haystack" == *"$needle"* ]] && pass "$label" \
    || fail "$label"
}

# ---------------------------------------------------------------------------
echo "== [S3-A] Sprint 3 skill inventory =="

# The 15 Sprint-3 skills across L1/L2/L3. Order matches S3-03..S3-17.
S3_SKILLS=(
  e2e-test-writer
  uat-executor
  regression-test-runner
  test-priority-engine
  mutation-test-runner
  environment-orchestrator
  chaos-injector
  cross-run-consistency
  test-result-analyzer
  coverage-analyzer
  observability-analyzer
  visual-ai-analyzer
  learning-loop-engine
  decision-recommender
  reconciliation-simulator
)

for skill in "${S3_SKILLS[@]}"; do
  if [[ -f "$SKILLS_DIR/$skill/SKILL.md" ]]; then
    pass "$skill SKILL.md present"
  else
    fail "$skill SKILL.md present"
  fi
  if [[ -d "$SKILLS_DIR/$skill/references" ]]; then
    REF_COUNT="$(find "$SKILLS_DIR/$skill/references" -maxdepth 1 -type f -name "*.md" | wc -l | tr -d ' ')"
    if (( REF_COUNT >= 2 )); then
      pass "$skill has at least 2 reference files (got $REF_COUNT)"
    else
      fail "$skill has at least 2 reference files (got $REF_COUNT)"
    fi
  else
    fail "$skill references/ directory present"
  fi
done

# Frontmatter sanity — every Sprint-3 skill declares `allowed-tools`.
# Matches the Sprint-2 harness shape; same load-bearing property.
for skill in "${S3_SKILLS[@]}"; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f "$f" ]] || continue
  if grep -q "^allowed-tools:" "$f"; then
    pass "$skill declares allowed-tools"
  else
    fail "$skill declares allowed-tools"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S3-B] io-standard output consistency =="

if [[ -f "$IO_STANDARD" ]]; then
  pass "io-standard.md exists"
else
  fail "io-standard.md exists"
fi

declare_output_check() {
  local skill="$1" output_name="$2"
  local f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f "$f" ]] || { fail "$skill output $output_name — SKILL.md missing"; return; }
  if grep -qF "$output_name" "$f"; then
    pass "$skill SKILL.md names output $output_name"
  else
    fail "$skill SKILL.md names output $output_name"
  fi
}

# Primary outputs per io-standard.md for each Sprint-3 skill.
declare_output_check "e2e-test-writer"         ".spec.ts"
declare_output_check "uat-executor"             "uat-raw-report.md"
declare_output_check "regression-test-runner"   "regression-report.md"
declare_output_check "regression-test-runner"   "regression-baseline.json"
declare_output_check "test-priority-engine"     "priority-plan.md"
declare_output_check "mutation-test-runner"     "mutation-report.md"
declare_output_check "environment-orchestrator" "env-setup.md"
declare_output_check "chaos-injector"           "chaos-report.md"
declare_output_check "cross-run-consistency"    "consistency-report.md"
declare_output_check "test-result-analyzer"     "test-results.md"
declare_output_check "test-result-analyzer"     "bug-tickets.md"
declare_output_check "coverage-analyzer"        "coverage-report.md"
declare_output_check "observability-analyzer"   "observability-report.md"
declare_output_check "visual-ai-analyzer"       "visual-report.md"
declare_output_check "learning-loop-engine"     "learning-report.md"
declare_output_check "decision-recommender"     "decision-package.md"
declare_output_check "reconciliation-simulator" "reconciliation-report.md"

# ---------------------------------------------------------------------------
echo "== [S3-C] Cross-skill reference coherence =="

# uat-executor fans out to test-result-analyzer and observability-analyzer
# via uat-raw-report.md. Both downstream skills must name it as input.
if grep -q "uat-raw-report.md" "$SKILLS_DIR/test-result-analyzer/SKILL.md"; then
  pass "test-result-analyzer consumes uat-raw-report.md"
else
  fail "test-result-analyzer consumes uat-raw-report.md"
fi
if grep -q "uat-raw-report" "$SKILLS_DIR/observability-analyzer/SKILL.md"; then
  pass "observability-analyzer consumes uat-raw-report.md"
else
  fail "observability-analyzer consumes uat-raw-report.md"
fi

# test-result-analyzer → learning-loop-engine via bug-tickets.md.
if grep -q "bug-tickets" "$SKILLS_DIR/learning-loop-engine/SKILL.md" \
   || grep -q "test-result-analyzer" "$SKILLS_DIR/learning-loop-engine/SKILL.md"; then
  pass "learning-loop-engine consumes test-result-analyzer output"
else
  fail "learning-loop-engine consumes test-result-analyzer output"
fi

# regression-test-runner → test-priority-engine via regression-baseline.json.
if grep -q "regression-baseline" "$SKILLS_DIR/test-priority-engine/SKILL.md"; then
  pass "test-priority-engine consumes regression-baseline.json"
else
  fail "test-priority-engine consumes regression-baseline.json"
fi

# regression-test-runner feeds learning-loop-engine (test-history mode).
if grep -q "regression-baseline" "$SKILLS_DIR/learning-loop-engine/SKILL.md"; then
  pass "learning-loop-engine consumes regression-baseline.json"
else
  fail "learning-loop-engine consumes regression-baseline.json"
fi

# coverage-analyzer reads rtm.md for scenario coverage.
if grep -q "rtm" "$SKILLS_DIR/coverage-analyzer/SKILL.md"; then
  pass "coverage-analyzer consumes rtm"
else
  fail "coverage-analyzer consumes rtm"
fi

# reconciliation-simulator is a financial-only input to
# release-decision-engine; it must declare that downstream.
if grep -q "release-decision-engine" "$SKILLS_DIR/reconciliation-simulator/SKILL.md"; then
  pass "reconciliation-simulator feeds release-decision-engine"
else
  fail "reconciliation-simulator feeds release-decision-engine"
fi

# decision-recommender consumes findings reports from L2 skills +
# learning-loop-engine recommendations. It is intentionally generic
# (any findings report), so the check targets the generic wording.
if grep -q "L2 skill reports" "$SKILLS_DIR/decision-recommender/SKILL.md" \
   || grep -q "learning-loop-engine" "$SKILLS_DIR/decision-recommender/SKILL.md"; then
  pass "decision-recommender consumes upstream findings reports"
else
  fail "decision-recommender consumes upstream findings reports"
fi

# learning-loop-engine is an L3 skill — it depends on historical runs
# and must explicitly declare its three modes.
LLE="$SKILLS_DIR/learning-loop-engine/SKILL.md"
for mode in "test-history" "production-feedback" "drift-analysis"; do
  if grep -q "$mode" "$LLE"; then
    pass "learning-loop-engine declares '$mode' mode"
  else
    fail "learning-loop-engine declares '$mode' mode"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S3-D] Gate contracts declared consistently =="

# Every Sprint-3 gating skill's gate contract string must appear in its
# SKILL.md. Distinct from run.sh's sentinels — this harness asserts a
# short, human-readable substring per skill so drift surfaces fast.
declare -a GATE_CONTRACTS=(
  "e2e-test-writer:Zero raw selectors in the test body"
  "uat-executor:Every failed step carries evidence"
  "regression-test-runner:P0 pass rate must be exactly 100%"
  "test-priority-engine:Every affected P0 test appears in the plan"
  "mutation-test-runner:zero surviving mutants in P0 code"
  "environment-orchestrator:Every component has a healthcheck"
  "cross-run-consistency:P0 scenarios must be strict-consistent"
  "coverage-analyzer:zero uncovered lines or branches in P0 code"
  "observability-analyzer:zero critical anomalies in P0 scenarios"
  "visual-ai-analyzer:zero critical visual regressions in P0"
  "reconciliation-simulator:zero invariant violations across every"
)

for pair in "${GATE_CONTRACTS[@]}"; do
  skill="${pair%%:*}"
  contract="${pair#*:}"
  f="$SKILLS_DIR/$skill/SKILL.md"
  if [[ -f "$f" ]] && grep -q "$contract" "$f"; then
    pass "$skill declares its gate contract"
  else
    fail "$skill declares its gate contract ('$contract')"
  fi
done

# chaos-injector + learning-loop-engine + decision-recommender + test-result-analyzer
# all declare multi-invariant gate contracts (3 or 4 invariants) — the
# exact phrasing differs but each must have a "## Gate" section.
for skill in chaos-injector learning-loop-engine decision-recommender test-result-analyzer; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  if grep -qE "^## Gate" "$f"; then
    pass "$skill declares a Gate section"
  else
    fail "$skill declares a Gate section"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S3-E] dev-ops + observability MCP sanity =="

# Shallow smoke — both dists parse + list_tools returns expected tools.
# The full smoke lives in run.sh [4d]/[4e]; this one keeps Sprint-3 CI
# standalone.
if [[ -f "$DO_DIST" ]] && node --check "$DO_DIST" 2>/dev/null; then
  pass "dev-ops dist parses"
else
  fail "dev-ops dist parses"
fi
if [[ -f "$OB_DIST" ]] && node --check "$OB_DIST" 2>/dev/null; then
  pass "observability dist parses"
else
  fail "observability dist parses"
fi

DO_OUT="$(GITHUB_TOKEN=test-token node "$DO_DIST" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s3","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF
)"
DO_LIST="$(echo "$DO_OUT" | grep '"id":2')"
assert_contains "dev-ops Sprint-3 sanity: tools/list returns do_trigger_pipeline" "do_trigger_pipeline" "$DO_LIST"
assert_contains "dev-ops Sprint-3 sanity: tools/list returns do_rollback" "do_rollback" "$DO_LIST"

OB_OUT="$(node "$OB_DIST" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s3","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ob_collect_metrics","arguments":{"payload":{"numTotalTests":1,"startTime":0,"endTime":100,"testResults":[{"testFilePath":"/s3/a.ts","assertionResults":[{"title":"t","fullName":"t","status":"passed","duration":10,"failureMessages":[],"location":{"line":1,"column":1}}]}]}}}}
EOF
)"
OB_LIST="$(echo "$OB_OUT" | grep '"id":2')"
OB_METRICS="$(echo "$OB_OUT" | grep '"id":3')"
assert_contains "observability Sprint-3 sanity: tools/list returns ob_health_dashboard" "ob_health_dashboard" "$OB_LIST"
assert_contains "observability Sprint-3 sanity: collect_metrics returns passed count" 'passed\": 1' "$OB_METRICS"

# ---------------------------------------------------------------------------
echo "== [S3-F] orchestrator PIPELINE-N coverage =="

# Every PIPELINE-N (1..7) must be declared in orchestrator.md. Drift
# here is how a pipeline gets silently dropped from the narrative.
if [[ -f "$ORCH" ]]; then
  pass "orchestrator.md exists"
  for n in 1 2 3 4 5 6 7; do
    if grep -qE "^### PIPELINE-${n}:" "$ORCH"; then
      pass "orchestrator declares PIPELINE-${n}"
    else
      fail "orchestrator declares PIPELINE-${n}"
    fi
  done
else
  fail "orchestrator.md exists"
fi

# Every Sprint-3 skill that cites a PIPELINE step must use the PIPELINE-N
# form consistently (not "pipeline N" or "stage N"). Spot-check a few.
declare -a PIPELINE_CITATIONS=(
  "uat-executor:PIPELINE-3"
  "regression-test-runner:PIPELINE-2"
  "reconciliation-simulator:PIPELINE-3"
  "coverage-analyzer:PIPELINE-5"
  "decision-recommender:PIPELINE-"
  "learning-loop-engine:PIPELINE-6"
)
for pair in "${PIPELINE_CITATIONS[@]}"; do
  skill="${pair%%:*}"
  cite="${pair#*:}"
  f="$SKILLS_DIR/$skill/SKILL.md"
  if grep -q "$cite" "$f"; then
    pass "$skill cites $cite"
  else
    fail "$skill cites $cite"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S3-G] Sprint 3 bug tracker closure =="

# Sprint 3 bugs must be marked FIXED in ROADMAP.md if any were logged.
# If Sprint 3 shipped clean with no bugs, the loop is empty and we
# record that explicitly so the harness doesn't silently no-op.
ROADMAP="$REPO_ROOT/ROADMAP.md"
if [[ -f "$ROADMAP" ]]; then
  pass "ROADMAP.md exists"
  # Count Sprint-3-scoped bug rows marked FIXED. A zero count is fine
  # (no bugs logged for Sprint 3); a row that says "Sprint 3" without
  # FIXED is a failure.
  UNFIXED_S3=$(grep -cE "^\| [0-9]+ \|.*Sprint 3.*\| (OPEN|IN PROGRESS|PENDING) \|" "$ROADMAP" || true)
  if (( UNFIXED_S3 == 0 )); then
    pass "no unresolved Sprint-3 bugs in ROADMAP"
  else
    fail "no unresolved Sprint-3 bugs in ROADMAP (found $UNFIXED_S3)"
  fi
else
  fail "ROADMAP.md exists"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
