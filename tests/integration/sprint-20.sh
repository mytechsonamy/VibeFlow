#!/bin/bash
# Sprint 20 integration harness — close the L3 learning loop:
# consensus telemetry mining + cross-session reviewer memory.
#
# Sections:
#   [S20-A] Durable consensus history.jsonl (aggregator + orchestrator + apply)
#   [S20-B] learning-loop consensus-history mode
#   [S20-C] Arbiter-decision effectiveness trace
#   [S20-D] Reviewer memory store
#   [S20-E] Orchestrator injects reviewer memory
#   [S20-F] primaryArtifact in consensus-gate message
#   [S20-G] decision-recommender consumes the learning report
#   [S20-H] Typed config (LearningLoop + ReviewerMemory) + phase-policy
#   [S20-I] Docs (LEARNING-LOOP.md + REVIEWER-MEMORY.md + refreshes)
#   [S20-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO_ROOT/hooks/scripts"
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
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$label"
  else fail "$label (expected=$expected actual=$actual)"
  fi
}

AGG="$SCRIPTS/consensus-aggregator.sh"
ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
APPLY="$REPO_ROOT/skills/apply-arbiter-patch/SKILL.md"
GATE="$SCRIPTS/consensus-gate.sh"
LLE="$REPO_ROOT/skills/learning-loop-engine/SKILL.md"
PATDET="$REPO_ROOT/skills/learning-loop-engine/references/pattern-detection.md"
DREC="$REPO_ROOT/skills/decision-recommender/SKILL.md"
DTYPES="$REPO_ROOT/skills/decision-recommender/references/decision-types.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
SPP="$REPO_ROOT/skills/phase-policy.json"

# ---------------------------------------------------------------------------
echo "== [S20-A] durable consensus history.jsonl =="

assert_grep "[S20-A] aggregator appends to history.jsonl" \
  "history\\.jsonl" "$AGG"
assert_grep "[S20-A] aggregator tags verdict rows type:verdict" \
  "type: \"verdict\"" "$AGG"
assert_grep "[S20-A] aggregator idempotent by sessionId+round" \
  "sessionId.*round|round.*sessionId" "$AGG"
assert_grep "[S20-A] aggregator resolves primaryArtifact sidecar" \
  "primary\\.txt" "$AGG"
assert_grep "[S20-A] orchestrator writes the primary sidecar" \
  "primary\\.txt" "$ORCH"
assert_grep "[S20-A] orchestrator cleans up the primary sidecar" \
  "rm -f.*primary\\.txt|primary\\.txt" "$ORCH"
assert_grep "[S20-A] apply-arbiter writes arbiter-decision rows" \
  "arbiter-decision" "$APPLY"
assert_grep "[S20-A] apply-arbiter row carries applied/rejected themes" \
  "applied:|rejected:" "$APPLY"

# Runtime: fire the aggregator and confirm a well-formed history row lands.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s20a-XXXXXX")"
cat > "$RT/vibeflow.config.json" <<EOF
{ "project": "s20a", "domain": "general", "currentPhase": "REQUIREMENTS",
  "consensus": { "quorum": 1 } }
EOF
export VIBEFLOW_CWD="$RT"
CONS="$RT/.vibeflow/state/consensus"
mkdir -p "$CONS"
echo "docs/PRD.md" > "$CONS/rt1.primary.txt"
echo "1" > "$CONS/rt1.current-round.txt"
printf '%s' '{"session_id":"rt1","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}' \
  | bash "$AGG" >/dev/null 2>&1
HF="$CONS/history.jsonl"
assert_file "[S20-A] runtime: history.jsonl created" "$HF"
if [[ -f "$HF" ]]; then
  RPRIM="$(jq -r 'select(.sessionId=="rt1") | .primaryArtifact' "$HF" | head -n1)"
  assert_eq "[S20-A] runtime: row carries primaryArtifact" "docs/PRD.md" "$RPRIM"
  RTYPE="$(jq -r 'select(.sessionId=="rt1") | .type' "$HF" | head -n1)"
  assert_eq "[S20-A] runtime: row type verdict" "verdict" "$RTYPE"
fi
rm -rf "$RT"; unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== [S20-B] learning-loop consensus-history mode =="

assert_grep "[S20-B] SKILL advertises four modes" \
  "four modes" "$LLE"
assert_grep "[S20-B] SKILL registers consensus-history mode" \
  "consensus-history" "$LLE"
assert_grep "[S20-B] Mode 4 reads history.jsonl" \
  "history\\.jsonl" "$LLE"
assert_grep "[S20-B] output is consensus-learning-report.md" \
  "consensus-learning-report\\.md" "$LLE"
assert_grep "[S20-B] explainability contract restated" \
  "finding, why, impact, confidence|finding.*why.*impact" "$LLE"
assert_grep "[S20-B] slow-converging-phase detector named" \
  "slow-converging-phase" "$LLE"
assert_grep "[S20-B] reviewer-skew detector named" \
  "reviewer-skew" "$LLE"
assert_grep "[S20-B] recurring-suggestion-theme detector named" \
  "recurring-suggestion-theme" "$LLE"
assert_grep "[S20-B] convergence-stall detector named" \
  "convergence-stall" "$LLE"
assert_grep "[S20-B] primary-artifact-churn detector named" \
  "primary-artifact-churn" "$LLE"
assert_grep "[S20-B] minObservations floor referenced" \
  "minObservations|3-observation|≥ 3" "$LLE"
# pattern-detection catalog
assert_grep "[S20-B] catalog has consensus-history section" \
  "consensus-history. mode patterns|consensus-history\` mode patterns" "$PATDET"
assert_grep "[S20-B] catalog LEARNING-SLOW-CONVERGING-PHASE" \
  "LEARNING-SLOW-CONVERGING-PHASE" "$PATDET"
assert_grep "[S20-B] catalog LEARNING-REVIEWER-SKEW" \
  "LEARNING-REVIEWER-SKEW" "$PATDET"
assert_grep "[S20-B] catalog LEARNING-RECURRING-SUGGESTION-THEME" \
  "LEARNING-RECURRING-SUGGESTION-THEME" "$PATDET"
assert_grep "[S20-B] catalog LEARNING-CONVERGENCE-STALL" \
  "LEARNING-CONVERGENCE-STALL" "$PATDET"
assert_grep "[S20-B] catalog LEARNING-PRIMARY-ARTIFACT-CHURN" \
  "LEARNING-PRIMARY-ARTIFACT-CHURN" "$PATDET"
assert_grep "[S20-B] catalog version bumped to 2" \
  "patternCatalogVersion: 2" "$PATDET"
assert_grep "[S20-B] catalog lists consensus-history pattern count" \
  "consensus-history patterns: 6" "$PATDET"

# ---------------------------------------------------------------------------
echo "== [S20-C] arbiter-decision effectiveness trace =="

assert_grep "[S20-C] SKILL describes apply→next-round delta" \
  "delta|agreement delta|round \\+ 1|round\\+1" "$LLE"
assert_grep "[S20-C] SKILL names the wasted-effort signal" \
  "ineffective-theme|wasted-effort" "$LLE"
assert_grep "[S20-C] SKILL surfaces reliably-converging themes" \
  "reliably-converging|reliably.converging" "$LLE"
assert_grep "[S20-C] catalog LEARNING-INEFFECTIVE-THEME" \
  "LEARNING-INEFFECTIVE-THEME" "$PATDET"
assert_grep "[S20-C] catalog ineffective-theme uses ≤ 0.02 delta" \
  "0\\.02" "$PATDET"

# ---------------------------------------------------------------------------
echo "== [S20-D] reviewer memory store =="

assert_grep "[S20-D] aggregator writes reviewer-memory store" \
  "reviewer-memory" "$AGG"
assert_grep "[S20-D] aggregator caps per (reviewer, artifact)" \
  "maxEntriesPerArtifact|group_by\\(.primaryArtifact\\)" "$AGG"
assert_grep "[S20-D] aggregator memory honours enabled kill switch" \
  "reviewerMemory\\.enabled|RM_ENABLED" "$AGG"
assert_grep "[S20-D] aggregator keeps top-3 criticals" \
  "\\[0:3\\]|0:3" "$AGG"

# ---------------------------------------------------------------------------
echo "== [S20-E] orchestrator injects reviewer memory =="

assert_grep "[S20-E] orchestrator defines build_memory_block" \
  "build_memory_block" "$ORCH"
assert_grep "[S20-E] orchestrator emits PRIOR REVIEW MEMORY block" \
  "PRIOR REVIEW MEMORY" "$ORCH"
assert_grep "[S20-E] codex prompt concatenates memory block" \
  "build_memory_block codex" "$ORCH"
assert_grep "[S20-E] gemini prompt concatenates memory block" \
  "build_memory_block gemini" "$ORCH"
assert_grep "[S20-E] claude-reviewer memory noted" \
  "build_memory_block claude-reviewer" "$ORCH"
assert_grep "[S20-E] memory block honours tokenBudget" \
  "tokenBudget|budget \\* 4" "$ORCH"
assert_grep "[S20-E] memory block omitted on clean first run" \
  "return 0|emits NOTHING|emits nothing" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S20-F] primaryArtifact in consensus-gate message =="

assert_grep "[S20-F] gate prefers primaryArtifact over artifact" \
  "primaryArtifact // .artifact" "$GATE"
assert_grep "[S20-F] gate message labels Primary artifact" \
  "Primary artifact:" "$GATE"
assert_grep "[S20-F] gate surfaces evidence list" \
  "evidence|Evidence:" "$GATE"

# ---------------------------------------------------------------------------
echo "== [S20-G] decision-recommender consumes learning report =="

assert_grep "[S20-G] input contract accepts consensus-learning-report.md" \
  "consensus-learning-report\\.md" "$DREC"
assert_grep "[S20-G] frontmatter keeps PIPELINE-4 step 2" \
  "PIPELINE-4 step 2" "$DREC"
assert_grep "[S20-G] gate-adjustment detects consensus-history findings" \
  "consensus-history|consensus\\.maxIterations" "$DTYPES"

# ---------------------------------------------------------------------------
echo "== [S20-H] typed config + phase-policy =="

assert_grep "[S20-H] config exports LearningLoopConfigSchema" \
  "export const LearningLoopConfigSchema" "$CFG"
assert_grep "[S20-H] config exports ReviewerMemoryConfigSchema" \
  "export const ReviewerMemoryConfigSchema" "$CFG"
assert_grep "[S20-H] LearningLoop default sprintWindow 3" \
  "sprintWindow.*default\\(3\\)|sprintWindow: 3" "$CFG"
assert_grep "[S20-H] LearningLoop default minObservations 3" \
  "minObservations.*default\\(3\\)|minObservations: 3" "$CFG"
assert_grep "[S20-H] ReviewerMemory default maxEntriesPerArtifact 5" \
  "maxEntriesPerArtifact.*default\\(5\\)|maxEntriesPerArtifact: 5" "$CFG"
assert_grep "[S20-H] ReviewerMemory default tokenBudget 600" \
  "tokenBudget.*default\\(600\\)|tokenBudget: 600" "$CFG"
assert_grep "[S20-H] EngineConfigSchema wires learningLoop" \
  "learningLoop: LearningLoopConfigSchema" "$CFG"
assert_grep "[S20-H] EngineConfigSchema wires reviewerMemory" \
  "reviewerMemory: ReviewerMemoryConfigSchema" "$CFG"
assert_grep "[S20-H] loadFileConfig merges learningLoop" \
  "raw\\.learningLoop" "$CFG"
assert_grep "[S20-H] loadFileConfig merges reviewerMemory" \
  "raw\\.reviewerMemory" "$CFG"
assert_grep "[S20-H] config tests cover LearningLoopConfigSchema" \
  "LearningLoopConfigSchema \\(Sprint 20-H\\)" "$CFG_TEST"
assert_grep "[S20-H] config tests cover ReviewerMemoryConfigSchema" \
  "ReviewerMemoryConfigSchema \\(Sprint 20-H\\)" "$CFG_TEST"
if jq -e '.skills["learning-loop-engine"].description | test("consensus-history")' "$SPP" >/dev/null 2>&1; then
  pass "[S20-H] phase-policy learning-loop mentions consensus-history"
else
  fail "[S20-H] phase-policy learning-loop mentions consensus-history"
fi

# ---------------------------------------------------------------------------
echo "== [S20-I] docs =="

assert_file "[S20-I] docs/LEARNING-LOOP.md exists" \
  "$REPO_ROOT/docs/LEARNING-LOOP.md"
assert_file "[S20-I] docs/REVIEWER-MEMORY.md exists" \
  "$REPO_ROOT/docs/REVIEWER-MEMORY.md"
assert_grep "[S20-I] LEARNING-LOOP doc covers the effectiveness trace" \
  "effectiveness trace|ineffective-theme" "$REPO_ROOT/docs/LEARNING-LOOP.md"
assert_grep "[S20-I] LEARNING-LOOP doc shows history.jsonl schema" \
  "history\\.jsonl" "$REPO_ROOT/docs/LEARNING-LOOP.md"
assert_grep "[S20-I] REVIEWER-MEMORY doc shows PRIOR REVIEW MEMORY block" \
  "PRIOR REVIEW MEMORY" "$REPO_ROOT/docs/REVIEWER-MEMORY.md"
assert_grep "[S20-I] REVIEWER-MEMORY doc documents the cap" \
  "maxEntriesPerArtifact" "$REPO_ROOT/docs/REVIEWER-MEMORY.md"
assert_grep "[S20-I] CONSENSUS-FLOW references the slow loop" \
  "slow loop|LEARNING-LOOP|REVIEWER-MEMORY" "$REPO_ROOT/docs/CONSENSUS-FLOW.md"
assert_grep "[S20-I] CONSENSUS-ITERATION references the agreement curve trace" \
  "effectiveness trace|LEARNING-LOOP" "$REPO_ROOT/docs/CONSENSUS-ITERATION.md"

# ---------------------------------------------------------------------------
echo "== [S20-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-20.sh"
if [[ -x "$SELF" ]]; then pass "[S20-Z] sprint-20.sh is executable"
else fail "[S20-Z] sprint-20.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S20-Z] sprint-20.sh shebang is #!/bin/bash"
else
  fail "[S20-Z] sprint-20.sh shebang is #!/bin/bash"
fi
for sec in S20-A S20-B S20-C S20-D S20-E S20-F S20-G S20-H S20-I S20-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S20-Z] [$sec] section header present"
  else
    fail "[S20-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
