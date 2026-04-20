#!/bin/bash
# Sprint 17 integration harness — iterative consensus +
# phase-specialists + HUMAN_APPROVAL_REQUIRED.
#
# Sections:
#   [S17-A] Iterative consensus rounds (aggregator + orchestrator)
#   [S17-B] Critical finding dedup
#   [S17-C] HUMAN_APPROVAL_REQUIRED status + humanOverrideNote
#   [S17-D] 6 phase-specialist agents
#   [S17-E] consensus-specialist dispatcher skill
#   [S17-F] Config + phase-policy
#   [S17-G] User docs
#   [S17-Z] Harness self-audit

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
echo "== [S17-A] iterative consensus rounds =="

AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"

assert_grep "[S17-A] aggregator reads current-round marker" \
  "current-round\.txt" "$AGG"
assert_grep "[S17-A] aggregator tags jsonl line with round field" \
  "round:\\\$round" "$AGG"
assert_grep "[S17-A] aggregator filters aggregation by current round" \
  "\\.round // 1" "$AGG"
assert_grep "[S17-A] aggregator composes rounds\[\] in verdict" \
  "rounds: \\(\\\$existingRounds" "$AGG"
assert_grep "[S17-A] aggregator writes finalRound field" \
  "finalRound:" "$AGG"
assert_grep "[S17-A] orchestrator Step 5 names maxIterations config" \
  "consensus\\.maxIterations" "$ORCH"
assert_grep "[S17-A] orchestrator Step 5 names approvalThreshold config" \
  "consensus\\.approvalThreshold" "$ORCH"
assert_grep "[S17-A] orchestrator Step 5 names iteration.enabled rollback" \
  "consensus\\.iteration\\.enabled" "$ORCH"
assert_grep "[S17-A] orchestrator documents round-N prompt embedding" \
  "PRIOR ROUND" "$ORCH"
assert_grep "[S17-A] orchestrator documents iteration stop reasons" \
  "iterationStopReason" "$ORCH"
assert_grep "[S17-A] orchestrator documents single-round fallback" \
  "Single-round fallback" "$ORCH"
assert_grep "[S17-A] orchestrator round-loop cleans up marker" \
  "rm -f \".*current-round\\.txt\"" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S17-B] critical finding dedup =="

REVIEWER="$REPO_ROOT/agents/claude-reviewer.md"

assert_grep "[S17-B] claude-reviewer schema documents title field" \
  "\"title\":" "$REVIEWER"
assert_grep "[S17-B] claude-reviewer schema documents target.line_range" \
  "line_range" "$REVIEWER"
assert_grep "[S17-B] claude-reviewer schema carries criticalIssues entry shape" \
  "load-bearing for dedup" "$REVIEWER"
assert_grep "[S17-B] claude-reviewer schema documents backward compat" \
  "criticalIssues: <integer>" "$REVIEWER"
assert_grep "[S17-B] aggregator parses criticalIssues as array or number" \
  "criticalIssues \\| type" "$AGG"
assert_grep "[S17-B] aggregator dedups by file+line_range" \
  "target\\.file // null" "$AGG"
assert_grep "[S17-B] aggregator dedups by Jaccard title similarity" \
  "jaccard_title" "$AGG"
assert_grep "[S17-B] aggregator preserves criticalRawCount for audit" \
  "criticalRawCount:" "$AGG"
assert_grep "[S17-B] aggregator preserves criticalDeduped[] for audit" \
  "criticalDeduped:" "$AGG"
assert_grep "[S17-B] aggregator requires rejected-majority (not agreement<0.5)" \
  "\\(\\.rejected \\* 2\\) > \\.total" "$AGG"

# ---------------------------------------------------------------------------
echo "== [S17-C] HUMAN_APPROVAL_REQUIRED + humanOverrideNote =="

CONSENSUS_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/consensus.ts"
VAL_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/validation.ts"
ENGINE_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/engine.ts"
TOOLS_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/tools.ts"
EVENTS_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/state/events.ts"
LSC="$REPO_ROOT/hooks/scripts/load-sdlc-context.sh"

assert_grep "[S17-C] consensus.ts declares HUMAN_APPROVAL_REQUIRED enum" \
  "HUMAN_APPROVAL_REQUIRED" "$CONSENSUS_TS"
assert_grep "[S17-C] consensus.ts registers alias human_approval" \
  "\"human_approval\"" "$CONSENSUS_TS"
assert_grep "[S17-C] consensus.ts exports isConsensusAdvanceValid" \
  "export function isConsensusAdvanceValid" "$CONSENSUS_TS"
assert_grep "[S17-C] validation.ts accepts HUMAN_APPROVAL_REQUIRED" \
  "HUMAN_APPROVAL_REQUIRED" "$VAL_TS"
assert_grep "[S17-C] engine.ts threads humanOverrideNote into transact context" \
  "humanOverrideNote" "$ENGINE_TS"
assert_grep "[S17-C] tools.ts schema accepts humanOverrideNote" \
  "humanOverrideNote" "$TOOLS_TS"
assert_grep "[S17-C] events schema makes humanOverrideNote optional on phase_advanced" \
  "humanOverrideNote: z\\.string" "$EVENTS_TS"
assert_grep "[S17-C] load-sdlc-context surfaces override event" \
  "HUMAN_APPROVAL_REQUIRED" "$LSC"
assert_grep "[S17-C] load-sdlc-context reads humanOverrideNote payload" \
  "humanOverrideNote" "$LSC"

# Engine + validation-consensus tests must still pass (this section
# just pins the surface, the actual behaviour tests live under
# mcp-servers/sdlc-engine/tests).
HUMAN_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/validation-human-approval.test.ts"
assert_file "[S17-C] validation-human-approval.test.ts exists" "$HUMAN_TEST"
assert_grep "[S17-C] validation-human-approval test covers pass-through" \
  "pass-through" "$HUMAN_TEST"
assert_grep "[S17-C] validation-human-approval test covers stale phase block" \
  "wrong phase" "$HUMAN_TEST"
assert_grep "[S17-C] validation-human-approval test covers NEEDS_REVISION still blocks" \
  "still blocks NEEDS_REVISION" "$HUMAN_TEST"

# ---------------------------------------------------------------------------
echo "== [S17-D] 6 phase-specialist agents =="

for agent in prd-rewriter design-spec-refiner adr-author test-strategy-refiner coverage-gap-filler runbook-editor; do
  f="$REPO_ROOT/agents/$agent.md"
  assert_file "[S17-D] $agent agent exists" "$f"
  assert_grep "[S17-D] $agent declares context: fork" \
    "^context: fork" "$f"
  assert_grep "[S17-D] $agent declares model: opus" \
    "^model: opus" "$f"
  assert_grep "[S17-D] $agent declares diff-first contract" \
    "diff-first" "$f"
done

# Phase contract guard on each agent.
for agent_phase in "prd-rewriter:REQUIREMENTS" \
                   "design-spec-refiner:DESIGN" \
                   "adr-author:ARCHITECTURE" \
                   "test-strategy-refiner:PLANNING" \
                   "coverage-gap-filler:TESTING" \
                   "runbook-editor:DEPLOYMENT"; do
  agent="${agent_phase%:*}"
  phase="${agent_phase#*:}"
  f="$REPO_ROOT/agents/$agent.md"
  assert_grep "[S17-D] $agent phase-contract names $phase" \
    "^Runs in \\*\\*$phase\\*\\*" "$f"
done

# ---------------------------------------------------------------------------
echo "== [S17-E] consensus-specialist dispatcher skill =="

DISPATCHER="$REPO_ROOT/skills/consensus-specialist/SKILL.md"

assert_file "[S17-E] consensus-specialist SKILL.md exists" "$DISPATCHER"
assert_grep "[S17-E] dispatcher allowed-tools includes Write" \
  "^allowed-tools:.*\\bWrite\\b" "$DISPATCHER"
assert_grep "[S17-E] dispatcher allowed-tools includes Bash(rm *) for drain" \
  "Bash\\(rm \\*\\)" "$DISPATCHER"
for agent in prd-rewriter design-spec-refiner adr-author test-strategy-refiner coverage-gap-filler runbook-editor; do
  assert_grep "[S17-E] dispatcher maps a phase to '$agent'" \
    "$agent" "$DISPATCHER"
done
assert_grep "[S17-E] dispatcher drains consensus-needed marker" \
  "consensus-needed\\.json" "$DISPATCHER"
assert_grep "[S17-E] dispatcher refuses second specialist without --force" \
  "\\-\\-force" "$DISPATCHER"

# ---------------------------------------------------------------------------
echo "== [S17-F] config + phase-policy =="

CONFIG_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CONFIG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
SKILL_POLICY="$REPO_ROOT/skills/phase-policy.json"

assert_grep "[S17-F] config.ts exports ConsensusConfigSchema" \
  "export const ConsensusConfigSchema" "$CONFIG_TS"
assert_grep "[S17-F] config.ts default maxIterations is 5" \
  "maxIterations.*default\\(5\\)" "$CONFIG_TS"
assert_grep "[S17-F] config.ts default approvalThreshold is 0.9" \
  "approvalThreshold.*default\\(0\\.9\\)" "$CONFIG_TS"
assert_grep "[S17-F] config.ts default iteration.enabled is true" \
  "enabled.*default\\(true\\)" "$CONFIG_TS"
assert_grep "[S17-F] config tests cover partial/default merge" \
  "applies defaults when field is omitted" "$CONFIG_TEST"
if jq -e '.skills["consensus-specialist"] != null' "$SKILL_POLICY" >/dev/null 2>&1; then
  pass "[S17-F] phase-policy registers consensus-specialist"
else
  fail "[S17-F] phase-policy registers consensus-specialist"
fi

# ---------------------------------------------------------------------------
echo "== [S17-G] user docs =="

ITER_DOC="$REPO_ROOT/docs/CONSENSUS-ITERATION.md"
SPEC_DOC="$REPO_ROOT/docs/SPECIALISTS.md"

assert_file "[S17-G] docs/CONSENSUS-ITERATION.md exists" "$ITER_DOC"
assert_file "[S17-G] docs/SPECIALISTS.md exists" "$SPEC_DOC"
assert_grep "[S17-G] CONSENSUS-ITERATION documents rounds[] schema" \
  "rounds\\[\\]" "$ITER_DOC"
assert_grep "[S17-G] CONSENSUS-ITERATION covers HUMAN_APPROVAL_REQUIRED" \
  "HUMAN_APPROVAL_REQUIRED" "$ITER_DOC"
assert_grep "[S17-G] SPECIALISTS lists all 6 agents" \
  "prd-rewriter" "$SPEC_DOC"
assert_grep "[S17-G] SPECIALISTS covers rollback recipe" \
  "git checkout HEAD" "$SPEC_DOC"

# ---------------------------------------------------------------------------
echo "== [S17.2] auto-register consensus + criteria =="

# v2.5.4: orchestrator must call sdlc_record_consensus after every
# terminal verdict so the validator's scope check has a lastConsensus
# to read. Without this, the entire automated chain up to /vibeflow:advance
# fails silently at the phase-gate.
assert_grep "[S17.2] orchestrator auto-calls sdlc_record_consensus" \
  "mcp__sdlc-engine__sdlc_record_consensus" "$ORCH"
assert_grep "[S17.2] orchestrator reads agreement from verdict.json" \
  "jq -r '\\.agreement // 0'" "$ORCH"
assert_grep "[S17.2] orchestrator reads criticalTotal from verdict.json" \
  "jq -r '\\.criticalTotal // 0'" "$ORCH"

# v2.5.4: prd-quality-analyzer auto-satisfies prd.approved (always) +
# testability.score>=60 (conditional on score). Removes the manual
# satisfy_criterion step for REQUIREMENTS exit.
PRD="$REPO_ROOT/skills/prd-quality-analyzer/SKILL.md"
assert_grep "[S17.2] prd-quality-analyzer auto-calls sdlc_satisfy_criterion" \
  "mcp__sdlc-engine__sdlc_satisfy_criterion" "$PRD"
assert_grep "[S17.2] prd-quality-analyzer satisfies prd.approved" \
  "\"criterion\": \"prd\\.approved\"" "$PRD"
assert_grep "[S17.2] prd-quality-analyzer conditionally satisfies testability gate" \
  "testability\\.score>=60" "$PRD"
assert_grep "[S17.2] prd-quality-analyzer guards with SCORE >= 60" \
  "if SCORE >= 60" "$PRD"

# ---------------------------------------------------------------------------
echo "== [S17-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-17.sh"
if [[ -x "$SELF" ]]; then
  pass "[S17-Z] sprint-17.sh is executable"
else
  fail "[S17-Z] sprint-17.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S17-Z] sprint-17.sh shebang is #!/bin/bash"
else
  fail "[S17-Z] sprint-17.sh shebang is #!/bin/bash"
fi
for sec in S17-A S17-B S17-C S17-D S17-E S17-F S17-G S17.2 S17-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S17-Z] [$sec] section header present"
  else
    fail "[S17-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
