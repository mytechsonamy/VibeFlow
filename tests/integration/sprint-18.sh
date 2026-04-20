#!/bin/bash
# Sprint 18 integration harness — full auto-satisfy rollout.
#
# Sections:
#   [S18-A] architecture-validator auto-satisfies adr.recorded
#   [S18-B] test-strategy-planner auto-satisfies test-strategy.approved
#   [S18-C] coverage-analyzer auto-satisfies coverage.met
#   [S18-D] mutation-test-runner Final Step + auto-satisfy
#   [S18-E] orchestrator auto-satisfies code.reviewed on DEVELOPMENT
#   [S18-F] quality-gates skill structure
#   [S18-G] deploy-verifier skill structure
#   [S18-H] AUTO-SATISFY.md + phase-policy registration
#   [S18-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label (missing: $path)"
  fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (no '$pattern' in $file)"
  fi
}

# ---------------------------------------------------------------------------
echo "== [S18-A] architecture-validator auto-satisfies adr.recorded =="

ARCH="$REPO_ROOT/skills/architecture-validator/SKILL.md"
assert_grep "[S18-A] architecture-validator calls sdlc_satisfy_criterion" \
  "mcp__sdlc-engine__sdlc_satisfy_criterion" "$ARCH"
assert_grep "[S18-A] architecture-validator satisfies adr.recorded" \
  "\"criterion\": \"adr\\.recorded\"" "$ARCH"
assert_grep "[S18-A] architecture-validator gates on verdict != BLOCKED" \
  "VERDICT != \"BLOCKED\"" "$ARCH"
assert_grep "[S18-A] architecture-validator has MCP-unavailable fallback" \
  "sdlc-engine MCP unavailable" "$ARCH"

# ---------------------------------------------------------------------------
echo "== [S18-B] test-strategy-planner auto-satisfies test-strategy.approved =="

TSP="$REPO_ROOT/skills/test-strategy-planner/SKILL.md"
assert_grep "[S18-B] test-strategy-planner calls sdlc_satisfy_criterion" \
  "mcp__sdlc-engine__sdlc_satisfy_criterion" "$TSP"
assert_grep "[S18-B] test-strategy-planner satisfies test-strategy.approved" \
  "\"criterion\": \"test-strategy\\.approved\"" "$TSP"
assert_grep "[S18-B] test-strategy-planner documents unconditional satisfy" \
  "unconditional" "$TSP"
assert_grep "[S18-B] test-strategy-planner notes sprint.planned stays manual" \
  "sprint\\.planned" "$TSP"

# ---------------------------------------------------------------------------
echo "== [S18-C] coverage-analyzer auto-satisfies coverage.met =="

COV="$REPO_ROOT/skills/coverage-analyzer/SKILL.md"
assert_grep "[S18-C] coverage-analyzer calls sdlc_satisfy_criterion" \
  "mcp__sdlc-engine__sdlc_satisfy_criterion" "$COV"
assert_grep "[S18-C] coverage-analyzer satisfies coverage.met" \
  "\"criterion\": \"coverage\\.met\"" "$COV"
assert_grep "[S18-C] coverage-analyzer gates on verdict == PASS" \
  "VERDICT == \"PASS\"" "$COV"
assert_grep "[S18-C] coverage-analyzer has MCP-unavailable fallback" \
  "sdlc-engine MCP unavailable" "$COV"

# ---------------------------------------------------------------------------
echo "== [S18-D] mutation-test-runner Final Step + auto-satisfy =="

MUT="$REPO_ROOT/skills/mutation-test-runner/SKILL.md"
assert_grep "[S18-D] mutation-test-runner has a Final Step" \
  "^## Final Step: Auto-Consensus" "$MUT"
assert_grep "[S18-D] mutation-test-runner writes consensus-needed marker" \
  "\"createdBy\": \"mutation-test-runner\"" "$MUT"
assert_grep "[S18-D] mutation-test-runner calls sdlc_satisfy_criterion" \
  "mcp__sdlc-engine__sdlc_satisfy_criterion" "$MUT"
assert_grep "[S18-D] mutation-test-runner satisfies mutation.score.acceptable" \
  "\"criterion\": \"mutation\\.score\\.acceptable\"" "$MUT"
assert_grep "[S18-D] mutation-test-runner gates on verdict == PASS" \
  "VERDICT == \"PASS\"" "$MUT"
assert_grep "[S18-D] mutation-test-runner has MCP-unavailable fallback" \
  "sdlc-engine MCP unavailable" "$MUT"

# ---------------------------------------------------------------------------
echo "== [S18-E] orchestrator auto-satisfies code.reviewed on DEVELOPMENT =="

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
assert_grep "[S18-E] orchestrator satisfies code.reviewed" \
  "\"criterion\": \"code\\.reviewed\"" "$ORCH"
assert_grep "[S18-E] orchestrator gates on PHASE == DEVELOPMENT" \
  "PHASE == DEVELOPMENT" "$ORCH"
assert_grep "[S18-E] orchestrator gates on APPROVED or HUMAN_APPROVAL_REQUIRED" \
  "HUMAN_APPROVAL_REQUIRED" "$ORCH"
assert_grep "[S18-E] orchestrator documents quality.gates.passed handoff" \
  "quality\\.gates\\.passed" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S18-F] quality-gates skill =="

QG="$REPO_ROOT/skills/quality-gates/SKILL.md"
assert_file "[S18-F] quality-gates SKILL.md exists" "$QG"
assert_grep "[S18-F] quality-gates DEVELOPMENT phase contract" \
  "Runs in \\*\\*DEVELOPMENT\\*\\*" "$QG"
assert_grep "[S18-F] quality-gates satisfies quality.gates.passed" \
  "\"criterion\": \"quality\\.gates\\.passed\"" "$QG"
assert_grep "[S18-F] quality-gates allowed-tools include test runner bash patterns" \
  "^allowed-tools:.*Bash\\(npm \\*\\)" "$QG"
assert_grep "[S18-F] quality-gates allowed-tools include pytest" \
  "Bash\\(pytest \\*\\)" "$QG"
assert_grep "[S18-F] quality-gates allowed-tools include dotnet" \
  "Bash\\(dotnet \\*\\)" "$QG"
assert_grep "[S18-F] quality-gates reports per-command exit codes" \
  "Exit code:" "$QG"
assert_grep "[S18-F] quality-gates gates on PASS verdict only" \
  "verdict == PASS" "$QG"

# ---------------------------------------------------------------------------
echo "== [S18-G] deploy-verifier skill =="

DV="$REPO_ROOT/skills/deploy-verifier/SKILL.md"
assert_file "[S18-G] deploy-verifier SKILL.md exists" "$DV"
assert_grep "[S18-G] deploy-verifier DEPLOYMENT phase contract" \
  "Runs in \\*\\*DEPLOYMENT\\*\\*" "$DV"
assert_grep "[S18-G] deploy-verifier calls do_pipeline_status" \
  "mcp__dev-ops__do_pipeline_status" "$DV"
assert_grep "[S18-G] deploy-verifier calls ob_health_dashboard" \
  "mcp__observability__ob_health_dashboard" "$DV"
assert_grep "[S18-G] deploy-verifier satisfies deployment.verified" \
  "\"criterion\": \"deployment\\.verified\"" "$DV"
assert_grep "[S18-G] deploy-verifier satisfies health.checks.passed" \
  "\"criterion\": \"health\\.checks\\.passed\"" "$DV"
assert_grep "[S18-G] deploy-verifier writes consensus-needed marker" \
  "\"createdBy\": \"deploy-verifier\"" "$DV"
assert_grep "[S18-G] deploy-verifier rollback hint references runbooks" \
  "docs/runbooks/" "$DV"
assert_grep "[S18-G] deploy-verifier no auto-rollback guardrail" \
  "No auto-rollback" "$DV"

# ---------------------------------------------------------------------------
echo "== [S18-H] AUTO-SATISFY.md + phase-policy registration =="

AS="$REPO_ROOT/docs/AUTO-SATISFY.md"
assert_file "[S18-H] docs/AUTO-SATISFY.md exists" "$AS"
for criterion in prd.approved adr.recorded test-strategy.approved \
                 coverage.met mutation.score.acceptable \
                 code.reviewed quality.gates.passed \
                 deployment.verified health.checks.passed; do
  assert_grep "[S18-H] AUTO-SATISFY documents '$criterion'" \
    "$criterion" "$AS"
done
assert_grep "[S18-H] AUTO-SATISFY marks design.approved as MANUAL" \
  "design\\.approved.*OPERATOR|OPERATOR.*design\\.approved" "$AS"
assert_grep "[S18-H] AUTO-SATISFY explains why manual criteria stay manual" \
  "Why some criteria stay manual" "$AS"
assert_grep "[S18-H] AUTO-SATISFY has troubleshooting section" \
  "Troubleshooting" "$AS"

SPP="$REPO_ROOT/skills/phase-policy.json"
if jq -e '.skills["quality-gates"] != null' "$SPP" >/dev/null 2>&1; then
  pass "[S18-H] phase-policy registers quality-gates"
else
  fail "[S18-H] phase-policy registers quality-gates"
fi
if jq -e '.skills["deploy-verifier"] != null' "$SPP" >/dev/null 2>&1; then
  pass "[S18-H] phase-policy registers deploy-verifier"
else
  fail "[S18-H] phase-policy registers deploy-verifier"
fi
if jq -e '.skills["quality-gates"].phases | index("DEVELOPMENT") != null' "$SPP" >/dev/null 2>&1; then
  pass "[S18-H] phase-policy: quality-gates phases include DEVELOPMENT"
else
  fail "[S18-H] phase-policy: quality-gates phases include DEVELOPMENT"
fi
if jq -e '.skills["deploy-verifier"].phases | index("DEPLOYMENT") != null' "$SPP" >/dev/null 2>&1; then
  pass "[S18-H] phase-policy: deploy-verifier phases include DEPLOYMENT"
else
  fail "[S18-H] phase-policy: deploy-verifier phases include DEPLOYMENT"
fi

# ---------------------------------------------------------------------------
echo "== [S18-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-18.sh"
if [[ -x "$SELF" ]]; then
  pass "[S18-Z] sprint-18.sh is executable"
else
  fail "[S18-Z] sprint-18.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S18-Z] sprint-18.sh shebang is #!/bin/bash"
else
  fail "[S18-Z] sprint-18.sh shebang is #!/bin/bash"
fi
for sec in S18-A S18-B S18-C S18-D S18-E S18-F S18-G S18-H S18-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S18-Z] [$sec] section header present"
  else
    fail "[S18-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
