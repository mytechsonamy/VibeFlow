#!/bin/bash
# Sprint 15 integration harness — auto-consensus loop + arbiter.
#
# Sections:
#   [S15-A] Orchestrator CLI output contract
#   [S15-B] Auto-consensus prose on 6 analysis skills
#   [S15-C] Phase-scoped consensus exit criteria + validator
#   [S15-D] load-sdlc-context marker drain + env advisory
#   [S15-E] Reviewer suggestion schema
#   [S15-F] consensus-arbiter skill
#   [S15-G] apply-arbiter-patch skill
#   [S15-H] User docs
#   [S15-I] Release sentinel
#   [S15-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S15-A] orchestrator CLI output contract =="

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
if grep -q "CLI Output Capture" "$ORCH"; then
  pass "[S15-A] orchestrator has CLI Output Capture subsection"
else
  fail "[S15-A] orchestrator has CLI Output Capture subsection"
fi
if grep -q "append_cli_verdict" "$ORCH"; then
  pass "[S15-A] orchestrator defines append_cli_verdict helper"
else
  fail "[S15-A] orchestrator defines append_cli_verdict helper"
fi
for token in "timeout 90" "SESSION_ID" "review-pending.json" "consensus-arbiter"; do
  if grep -q "$token" "$ORCH"; then
    pass "[S15-A] orchestrator references '$token'"
  else
    fail "[S15-A] orchestrator references '$token'"
  fi
done
# Frontmatter must allow the new bash commands
for tool in "Write" "jq" "timeout" "rm" "mkdir"; do
  if head -10 "$ORCH" | grep -q "$tool"; then
    pass "[S15-A] orchestrator allowed-tools include '$tool'"
  else
    fail "[S15-A] orchestrator allowed-tools include '$tool'"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S15-B] auto-consensus prose =="

for skill in prd-quality-analyzer architecture-validator test-strategy-planner traceability-engine coverage-analyzer release-decision-engine; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  if grep -q "Final Step: Auto-Consensus" "$f"; then
    pass "[S15-B] $skill has Final Step: Auto-Consensus"
  else
    fail "[S15-B] $skill has Final Step: Auto-Consensus"
  fi
  if grep -q "VF_SKIP_AUTO_CONSENSUS" "$f"; then
    pass "[S15-B] $skill honours VF_SKIP_AUTO_CONSENSUS"
  else
    fail "[S15-B] $skill honours VF_SKIP_AUTO_CONSENSUS"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S15-C] phase-scoped consensus exit criteria =="

PHASES_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/phases.ts"
for criterion in \
  "consensus.requirements.approved" \
  "consensus.design.approved" \
  "consensus.architecture.approved" \
  "consensus.planning.approved" \
  "consensus.testing.approved" \
  "consensus.deployment.approved"; do
  if grep -q "\"$criterion\"" "$PHASES_TS"; then
    pass "[S15-C] phases.ts declares '$criterion'"
  else
    fail "[S15-C] phases.ts declares '$criterion'"
  fi
done
# DEVELOPMENT must NOT carry a scoped criterion (commit-time marker
# handles it). Explicit sentinel so nobody silently tightens the
# gate and double-gates DEV commits.
if grep -E '"consensus\.development\.approved"' "$PHASES_TS" >/dev/null 2>&1; then
  fail "[S15-C] DEVELOPMENT must NOT have a scoped consensus criterion"
else
  pass "[S15-C] DEVELOPMENT correctly omits consensus.development.approved"
fi

VAL_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/validation.ts"
if grep -q "CONSENSUS_CRITERION_PATTERN" "$VAL_TS"; then
  pass "[S15-C] validator imports CONSENSUS_CRITERION_PATTERN"
else
  fail "[S15-C] validator imports CONSENSUS_CRITERION_PATTERN"
fi
if grep -q "lastConsensusPhase" "$VAL_TS"; then
  pass "[S15-C] validator consumes lastConsensusPhase"
else
  fail "[S15-C] validator consumes lastConsensusPhase"
fi

# ---------------------------------------------------------------------------
echo "== [S15-D] load-sdlc-context marker drain =="

LSC="$REPO_ROOT/hooks/scripts/load-sdlc-context.sh"
if grep -q "review-pending.json" "$LSC"; then
  pass "[S15-D] load-sdlc-context reads review-pending.json"
else
  fail "[S15-D] load-sdlc-context reads review-pending.json"
fi
if grep -q "ACTION REQUIRED" "$LSC"; then
  pass "[S15-D] marker emits a strong ACTION REQUIRED instruction"
else
  fail "[S15-D] marker emits a strong ACTION REQUIRED instruction"
fi
if grep -q "VF_SKIP_AUTO_CONSENSUS" "$LSC"; then
  pass "[S15-D] load-sdlc-context surfaces VF_SKIP_AUTO_CONSENSUS"
else
  fail "[S15-D] load-sdlc-context surfaces VF_SKIP_AUTO_CONSENSUS"
fi

# ---------------------------------------------------------------------------
echo "== [S15-E] reviewer suggestion schema =="

REVIEWER="$REPO_ROOT/agents/claude-reviewer.md"
for field in "phase_relevance" "proposed_change" "priority" "line_range"; do
  if grep -q "$field" "$REVIEWER"; then
    pass "[S15-E] claude-reviewer schema mentions '$field'"
  else
    fail "[S15-E] claude-reviewer schema mentions '$field'"
  fi
done
# target is a nested object { file, line_range }; check both pieces
if grep -qE '"target"' "$REVIEWER" && grep -qE '"file"' "$REVIEWER"; then
  pass "[S15-E] claude-reviewer schema mentions target.file"
else
  fail "[S15-E] claude-reviewer schema mentions target.file"
fi

# ---------------------------------------------------------------------------
echo "== [S15-F] consensus-arbiter skill =="

ARB="$REPO_ROOT/skills/consensus-arbiter/SKILL.md"
if [[ -f "$ARB" ]]; then
  pass "[S15-F] consensus-arbiter SKILL.md exists"
else
  fail "[S15-F] consensus-arbiter SKILL.md exists"
fi
for token in "APPLY" "DEFER" "REJECT" "phase_relevance" "iteration" "arbiter-decisions.md" "manifest.json"; do
  if grep -q "$token" "$ARB"; then
    pass "[S15-F] arbiter references '$token'"
  else
    fail "[S15-F] arbiter references '$token'"
  fi
done
# Must NOT allow Edit on source files (diff-first contract)
if head -10 "$ARB" | grep -qE 'allowed-tools:[^\n]*\bEdit\b'; then
  fail "[S15-F] arbiter must NOT have Edit in allowed-tools (diff-first)"
else
  pass "[S15-F] arbiter correctly omits Edit (diff-first)"
fi

# ---------------------------------------------------------------------------
echo "== [S15-G] apply-arbiter-patch skill =="

APPLY="$REPO_ROOT/skills/apply-arbiter-patch/SKILL.md"
if [[ -f "$APPLY" ]]; then
  pass "[S15-G] apply-arbiter-patch SKILL.md exists"
else
  fail "[S15-G] apply-arbiter-patch SKILL.md exists"
fi
for flag in "--yes" "--run-tests" "--dry-run"; do
  if grep -q -- "$flag" "$APPLY"; then
    pass "[S15-G] apply skill documents '$flag' flag"
  else
    fail "[S15-G] apply skill documents '$flag' flag"
  fi
done
if grep -q "git apply" "$APPLY"; then
  pass "[S15-G] apply skill uses git apply"
else
  fail "[S15-G] apply skill uses git apply"
fi
if grep -q "git checkout HEAD" "$APPLY"; then
  pass "[S15-G] apply skill documents rollback command"
else
  fail "[S15-G] apply skill documents rollback command"
fi

# ---------------------------------------------------------------------------
echo "== [S15-H] user docs =="

for doc in CONSENSUS-FLOW.md ARBITER.md; do
  f="$REPO_ROOT/docs/$doc"
  if [[ -f "$f" ]]; then
    pass "[S15-H] docs/$doc exists"
  else
    fail "[S15-H] docs/$doc exists"
  fi
done

# CONSENSUS-FLOW must describe the 4 layers
CFL="$REPO_ROOT/docs/CONSENSUS-FLOW.md"
if [[ -f "$CFL" ]]; then
  # Doc uses the L1/L2/L3/L4 shorthand as well as "Four layers".
  for token in "L1:" "L2:" "L3:" "L4:" "VF_SKIP_AUTO_CONSENSUS"; do
    if grep -q "$token" "$CFL"; then
      pass "[S15-H] CONSENSUS-FLOW.md covers '$token'"
    else
      fail "[S15-H] CONSENSUS-FLOW.md covers '$token'"
    fi
  done
fi

# ARBITER must describe decision matrix + rollback
ARB_DOC="$REPO_ROOT/docs/ARBITER.md"
if [[ -f "$ARB_DOC" ]]; then
  for token in "APPLY" "DEFER" "REJECT" "git checkout"; do
    if grep -q "$token" "$ARB_DOC"; then
      pass "[S15-H] ARBITER.md covers '$token'"
    else
      fail "[S15-H] ARBITER.md covers '$token'"
    fi
  done
fi

# ---------------------------------------------------------------------------
echo "== [S15-I] release sentinel =="

PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"
if jq -e '.version == "2.3.0"' "$PLUGIN" >/dev/null 2>&1; then
  pass "[S15-I] plugin.json version == 2.3.0"
else
  fail "[S15-I] plugin.json version == 2.3.0"
fi
if [[ -f "$REPO_ROOT/release-notes/2.3.0.md" ]]; then
  pass "[S15-I] release-notes/2.3.0.md exists"
else
  fail "[S15-I] release-notes/2.3.0.md exists"
fi

# skills/phase-policy.json must register the two new skills
SPP="$REPO_ROOT/skills/phase-policy.json"
for skill in consensus-arbiter apply-arbiter-patch; do
  if jq -e --arg s "$skill" '.skills[$s] != null' "$SPP" >/dev/null 2>&1; then
    pass "[S15-I] phase-policy registers '$skill'"
  else
    fail "[S15-I] phase-policy registers '$skill'"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S15-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-15.sh"
if [[ -x "$SELF" ]]; then
  pass "[S15-Z] sprint-15.sh is executable"
else
  fail "[S15-Z] sprint-15.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S15-Z] sprint-15.sh shebang is #!/bin/bash"
else
  fail "[S15-Z] sprint-15.sh shebang is #!/bin/bash"
fi
for sec in "S15-A" "S15-B" "S15-C" "S15-D" "S15-E" "S15-F" "S15-G" "S15-H" "S15-I" "S15-Z"; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S15-Z] [$sec] section header present"
  else
    fail "[S15-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
