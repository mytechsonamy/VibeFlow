#!/bin/bash
# Sprint 19 integration harness — primary-artifact refocus + end-to-end
# phase automation.
#
# Sections:
#   [S19-A] Marker schema v2 across 8 analysis skills
#   [S19-B] Orchestrator primary-artifact resolution + prompt
#   [S19-C] Aggregator status rule refactor
#   [S19-D] Specialist guardrail (4-case)
#   [S19-E] Apply auto-chain (Step 9)
#   [S19-F] phase-runner skill
#   [S19-G] PhaseRunnerConfigSchema + phase-policy
#   [S19-H] Docs (PRIMARY-ARTIFACT.md + updates)
#   [S19-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then pass "$label"; else fail "$label (missing: $path)"; fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then pass "$label"
  else fail "$label (no '$pattern' in $file)"
  fi
}

# ---------------------------------------------------------------------------
echo "== [S19-A] marker schema v2 across 8 analysis skills =="

for skill in prd-quality-analyzer architecture-validator test-strategy-planner traceability-engine coverage-analyzer mutation-test-runner release-decision-engine deploy-verifier; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  assert_grep "[S19-A] $skill marker carries primaryArtifact" \
    "\"primaryArtifact\":" "$f"
  assert_grep "[S19-A] $skill marker carries evidence[]" \
    "\"evidence\":" "$f"
  assert_grep "[S19-A] $skill marker keeps legacy artifact field" \
    "\"artifact\":" "$f"
done

# quality-gates legitimately does NOT write a marker — it satisfies
# quality.gates.passed directly without a consensus step. Confirm
# that's still the case: no "requiredCommand" JSON field anywhere
# (the skill's one reference to `consensus-needed.json` is in prose
# explaining WHY it doesn't write the marker).
QG="$REPO_ROOT/skills/quality-gates/SKILL.md"
if grep -q '"requiredCommand":' "$QG"; then
  fail "[S19-A] quality-gates stayed marker-less (no consensus-needed.json write)"
else
  pass "[S19-A] quality-gates stayed marker-less (no consensus-needed.json write)"
fi

# ---------------------------------------------------------------------------
echo "== [S19-B] orchestrator primary-artifact resolution =="

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
assert_grep "[S19-B] orchestrator parses primaryArtifact field" \
  "jq.*primaryArtifact" "$ORCH"
assert_grep "[S19-B] orchestrator parses evidence array" \
  "evidence\[\]" "$ORCH"
assert_grep "[S19-B] orchestrator has legacy single-file fallback" \
  "legacy single-file invocation|legacy path" "$ORCH"
assert_grep "[S19-B] orchestrator prompt names PRIMARY ARTIFACT UNDER REVIEW" \
  "PRIMARY ARTIFACT UNDER REVIEW" "$ORCH"
assert_grep "[S19-B] orchestrator prompt names SUPPORTING EVIDENCE" \
  "SUPPORTING EVIDENCE" "$ORCH"
assert_grep "[S19-B] orchestrator notes evidence distillation ≤500 tokens" \
  "500 token" "$ORCH"
assert_grep "[S19-B] orchestrator handles >30k token primary with excerpts" \
  "30 000 tokens|30k token" "$ORCH"
assert_grep "[S19-B] orchestrator uses build_review_prompt shared helper" \
  "build_review_prompt" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S19-C] aggregator status rule refactor =="

AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
assert_grep "[S19-C] aggregator keeps rejected-majority rule" \
  "\(.rejected \* 2\) > .total" "$AGG"
assert_grep "[S19-C] aggregator requires rejected≥1 for critical escalation" \
  ".rejected >= 1 and .criticalTotal >= 2" "$AGG"
assert_grep "[S19-C] aggregator APPROVED rule unchanged" \
  ".agreement >= 0.9 and .criticalTotal == 0" "$AGG"
# Sentinel: the old unconditional criticalTotal>=2 → REJECTED path
# must NOT reappear (regression guard for FlowBridge_TR false-reject).
if grep -qE '^\s+if \.criticalTotal >= 2 then "REJECTED"' "$AGG"; then
  fail "[S19-C] aggregator dropped unconditional criticalTotal>=2 → REJECTED"
else
  pass "[S19-C] aggregator dropped unconditional criticalTotal>=2 → REJECTED"
fi

# Runtime regression: 2 NEEDS_REVISION + 1 APPROVED + criticalTotal=2
# + rejected=0 should land as NEEDS_REVISION (was REJECTED pre-S19-C).
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s19c-XXXXXX")"
export VIBEFLOW_CWD="$DIR"
cat > "$DIR/vibeflow.config.json" <<EOF
{"project":"sp19","domain":"general","currentPhase":"REQUIREMENTS","consensus":{"quorum":3}}
EOF
mkdir -p "$DIR/.vibeflow/state/consensus"
CONS_DIR="$DIR/.vibeflow/state/consensus"
# Seed two NEEDS_REVISION + one APPROVED, each with one structured critical
# item. After dedup across reviewers (same file + line_range) criticalTotal
# could still be 2+ (three distinct entries if titles differ).
SCRIPTS="$REPO_ROOT/hooks/scripts"
for entry in \
  '{"session_id":"s19c","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[{\"id\":\"c1\",\"target\":{\"file\":\"docs/prd.md\",\"line_range\":[10,20]},\"title\":\"TCR formula missing\",\"rationale\":\"x\"}]}"}]}}' \
  '{"session_id":"s19c","subagent_type":"codex-reviewer","tool_response":{"content":[{"text":"{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[{\"id\":\"c2\",\"target\":{\"file\":\"docs/prd.md\",\"line_range\":[30,40]},\"title\":\"data residency undefined\",\"rationale\":\"y\"}]}"}]}}' \
  '{"session_id":"s19c","subagent_type":"gemini-reviewer","tool_response":{"content":[{"text":"{\"verdict\":\"APPROVED\",\"criticalIssues\":[]}"}]}}'; do
  printf '%s' "$entry" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
done
V="$CONS_DIR/s19c.verdict.json"
if [[ -f "$V" ]]; then
  STATUS="$(jq -r '.status' "$V")"
  CRIT="$(jq -r '.criticalTotal' "$V")"
  REJECTED="$(jq -r '.rejected' "$V")"
  if [[ "$STATUS" == "NEEDS_REVISION" ]]; then
    pass "[S19-C] 2 NEEDS_REVISION + 1 APPROVED + critical=$CRIT + rejected=$REJECTED → NEEDS_REVISION"
  else
    fail "[S19-C] expected NEEDS_REVISION, got $STATUS (critical=$CRIT, rejected=$REJECTED)"
  fi
else
  fail "[S19-C] verdict.json written after 3 reviewers"
fi
rm -rf "$DIR"
unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== [S19-D] specialist guardrail (4-case) =="

SPEC="$REPO_ROOT/skills/consensus-specialist/SKILL.md"
assert_grep "[S19-D] specialist reads verdict.rejected count" \
  "REJECTED_COUNT|jq -r '.rejected" "$SPEC"
assert_grep "[S19-D] specialist 4-case matrix documented" \
  "4-case decision matrix|4-case guardrail" "$SPEC"
assert_grep "[S19-D] specialist dispatches NEEDS_REVISION + HUMAN_APPROVAL_REQUIRED" \
  "NEEDS_REVISION.*HUMAN_APPROVAL_REQUIRED" "$SPEC"
assert_grep "[S19-D] specialist stops on genuine REJECTED (rejected≥1)" \
  "Genuine reject|genuine reject" "$SPEC"

# ---------------------------------------------------------------------------
echo "== [S19-E] apply auto-chain (Step 9) =="

APPLY="$REPO_ROOT/skills/apply-arbiter-patch/SKILL.md"
assert_grep "[S19-E] apply has Step 9 auto-chain section" \
  "^### Step 9: Auto-chain" "$APPLY"
assert_grep "[S19-E] apply --no-chain flag documented" \
  "\\-\\-no-chain" "$APPLY"
assert_grep "[S19-E] apply respects VF_SKIP_AUTO_CHAIN env" \
  "VF_SKIP_AUTO_CHAIN" "$APPLY"
assert_grep "[S19-E] apply honours consensus.maxIterations ceiling" \
  "consensus\\.maxIterations|max-iterations-reached" "$APPLY"
assert_grep "[S19-E] apply convergence-stall guard" \
  "Convergence [Ss]tall|convergence-stalled|stall guard" "$APPLY"
assert_grep "[S19-E] apply iteration tracked via verdict.round (not manifest.iteration)" \
  "verdict\\.round|verdict\\.json\\.round" "$APPLY"
assert_grep "[S19-E] apply next marker carries autoChain metadata" \
  "autoChain" "$APPLY"
assert_grep "[S19-E] apply Final Step renamed Auto-chain" \
  "Final Step: Auto-chain" "$APPLY"

# ---------------------------------------------------------------------------
echo "== [S19-F] phase-runner skill =="

PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
assert_file "[S19-F] phase-runner SKILL.md exists" "$PR"
assert_grep "[S19-F] phase-runner allowed-tools include mcp__sdlc-engine__" \
  "mcp__sdlc-engine__" "$PR"
assert_grep "[S19-F] phase-runner allowed-tools include sdlc_advance_phase" \
  "sdlc_advance_phase" "$PR"
assert_grep "[S19-F] phase-runner respects phaseRunner.autoAdvance" \
  "phaseRunner\\.autoAdvance|autoAdvance" "$PR"
assert_grep "[S19-F] phase-runner respects maxConvergenceAttempts" \
  "maxConvergenceAttempts" "$PR"
assert_grep "[S19-F] phase-runner refuses phase mismatch" \
  "phase-runner mismatch|phase mismatch" "$PR"
for phase in REQUIREMENTS DESIGN ARCHITECTURE PLANNING DEVELOPMENT TESTING DEPLOYMENT; do
  assert_grep "[S19-F] phase-runner map mentions $phase" \
    "\\b$phase\\b" "$PR"
done

# ---------------------------------------------------------------------------
echo "== [S19-G] PhaseRunnerConfigSchema + phase-policy =="

CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
assert_grep "[S19-G] config.ts exports PhaseRunnerConfigSchema" \
  "export const PhaseRunnerConfigSchema" "$CFG"
assert_grep "[S19-G] config.ts default autoAdvance=true" \
  "autoAdvance:.*default\\(true\\)" "$CFG"
assert_grep "[S19-G] config.ts default maxConvergenceAttempts=3" \
  "maxConvergenceAttempts:.*default\\(3\\)" "$CFG"
assert_grep "[S19-G] EngineConfigSchema wires phaseRunner" \
  "phaseRunner: PhaseRunnerConfigSchema" "$CFG"

CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
assert_grep "[S19-G] config tests cover PhaseRunnerConfigSchema defaults" \
  "PhaseRunnerConfigSchema \\(Sprint 19-G\\)" "$CFG_TEST"

SPP="$REPO_ROOT/skills/phase-policy.json"
if jq -e '.skills["phase-runner"] != null' "$SPP" >/dev/null 2>&1; then
  pass "[S19-G] phase-policy registers phase-runner"
else
  fail "[S19-G] phase-policy registers phase-runner"
fi

# ---------------------------------------------------------------------------
echo "== [S19-H] docs updates =="

PRIMARY="$REPO_ROOT/docs/PRIMARY-ARTIFACT.md"
assert_file "[S19-H] docs/PRIMARY-ARTIFACT.md exists" "$PRIMARY"
for token in "primaryArtifact" "evidence\\[\\]" "marker v2" "Per-phase primary" "Backward compatibility" ">30k"; do
  assert_grep "[S19-H] PRIMARY-ARTIFACT covers '$token'" "$token" "$PRIMARY"
done

# ---------------------------------------------------------------------------
echo "== [S19-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-19.sh"
if [[ -x "$SELF" ]]; then pass "[S19-Z] sprint-19.sh is executable"
else fail "[S19-Z] sprint-19.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S19-Z] sprint-19.sh shebang is #!/bin/bash"
else
  fail "[S19-Z] sprint-19.sh shebang is #!/bin/bash"
fi
for sec in S19-A S19-B S19-C S19-D S19-E S19-F S19-G S19-H S19-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S19-Z] [$sec] section header present"
  else
    fail "[S19-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
