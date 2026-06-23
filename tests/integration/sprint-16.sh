#!/bin/bash
# Sprint 16 integration harness — deterministic auto-consensus chain.
#
# Sections:
#   [S16-A] consensus-gate.sh script + hooks.json wiring
#   [S16-B] orchestrator + arbiter + apply drain consensus-needed.json
#   [S16-C] 6 analysis skills Write consensus-needed.json marker
#   [S16-D] docs/CONSENSUS-FLOW.md Layer 2 rewrite
#   [S16-Z] Harness self-audit

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
echo "== [S16-A] consensus-gate.sh + hooks.json wiring =="

GATE="$REPO_ROOT/hooks/scripts/consensus-gate.sh"
assert_file "[S16-A] consensus-gate.sh exists" "$GATE"

if [[ -x "$GATE" ]]; then
  pass "[S16-A] consensus-gate.sh is executable"
else
  fail "[S16-A] consensus-gate.sh is executable"
fi

if head -1 "$GATE" | grep -q '^#!/bin/bash'; then
  pass "[S16-A] consensus-gate.sh shebang is #!/bin/bash"
else
  fail "[S16-A] consensus-gate.sh shebang is #!/bin/bash"
fi

# Canonical behaviours the script MUST have
for token in \
  "consensus-needed.json" \
  "VF_SKIP_CONSENSUS_GATE" \
  "vibeflow:consensus-orchestrator" \
  "vibeflow:consensus-arbiter" \
  "vibeflow:apply-arbiter-patch" \
  "requiredCommand" \
  "exit 2"; do
  assert_grep "[S16-A] script references '$token'" "$token" "$GATE"
done

# Fail-safe sentinels
for token in 'vf_have_jq' 'vf_state_dir' '\.vibeflow/\*'; do
  assert_grep "[S16-A] script fail-safe token '$token' present" "$token" "$GATE"
done

HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|Write|Edit") | .hooks[] | select(.command | test("consensus-gate"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "[S16-A] hooks.json PreToolUse registers consensus-gate on Bash|Write|Edit"
else
  fail "[S16-A] hooks.json PreToolUse registers consensus-gate on Bash|Write|Edit"
fi

# ---------------------------------------------------------------------------
echo "== [S16-B] orchestrator + arbiter + apply drain consensus-needed.json =="

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
ARB="$REPO_ROOT/skills/consensus-arbiter/SKILL.md"
APPLY="$REPO_ROOT/skills/apply-arbiter-patch/SKILL.md"

assert_grep "[S16-B] orchestrator drains consensus-needed.json" \
  "rm -f .*consensus-needed\.json" "$ORCH"
assert_grep "[S16-B] arbiter drains consensus-needed.json" \
  "rm -f .*consensus-needed\.json" "$ARB"
assert_grep "[S16-B] apply drains consensus-needed.json" \
  "rm -f .*consensus-needed\.json" "$APPLY"

# allowed-tools must include Bash(rm *) on arbiter + apply
assert_grep "[S16-B] arbiter allowed-tools include Bash(rm *)" \
  "allowed-tools:.*Bash\(rm \*\)" "$ARB"
assert_grep "[S16-B] apply allowed-tools include Bash(rm *)" \
  "allowed-tools:.*Bash\(rm \*\)" "$APPLY"

# The orchestrator must drain on all three verdict statuses
for status in APPROVED NEEDS_REVISION REJECTED; do
  assert_grep "[S16-B] orchestrator drain covers '$status'" "$status" "$ORCH"
done

# ---------------------------------------------------------------------------
echo "== [S16-C] 6 analysis skills Write consensus-needed.json marker =="

for skill in prd-quality-analyzer architecture-validator test-strategy-planner traceability-engine coverage-analyzer release-decision-engine; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  assert_file "[S16-C] $skill SKILL.md exists" "$f"
  # Marker-writing prose: the path and the required JSON keys
  assert_grep "[S16-C] $skill writes consensus-needed.json marker" \
    "consensus-needed\.json" "$f"
  assert_grep "[S16-C] $skill marker names createdBy: $skill" \
    "\"createdBy\": \"$skill\"" "$f"
  assert_grep "[S16-C] $skill marker names requiredCommand" \
    "\"requiredCommand\":" "$f"
  # Write must be in allowed-tools (required to drop the marker file)
  if head -10 "$f" | grep -qE 'allowed-tools:.*\bWrite\b'; then
    pass "[S16-C] $skill allowed-tools include Write"
  else
    fail "[S16-C] $skill allowed-tools include Write"
  fi
  # Backward-compat with [S15-B] — "Final Step: Auto-Consensus" substring
  # must still be present so sprint-15.sh doesn't regress.
  assert_grep "[S16-C] $skill preserves 'Final Step: Auto-Consensus' header (S15-B compat)" \
    "Final Step: Auto-Consensus" "$f"
  # VF_SKIP_AUTO_CONSENSUS escape hatch still surfaced
  assert_grep "[S16-C] $skill still surfaces VF_SKIP_AUTO_CONSENSUS" \
    "VF_SKIP_AUTO_CONSENSUS" "$f"
done

# ---------------------------------------------------------------------------
echo "== [S16-D] docs/CONSENSUS-FLOW.md Layer 2 rewrite =="

CFL="$REPO_ROOT/docs/CONSENSUS-FLOW.md"
assert_file "[S16-D] CONSENSUS-FLOW.md exists" "$CFL"

for token in \
  "consensus-needed\.json" \
  "Sprint 16-A" \
  "consensus-gate" \
  "VF_SKIP_CONSENSUS_GATE" \
  "Layer 2 in detail"; do
  assert_grep "[S16-D] CONSENSUS-FLOW covers '$token'" "$token" "$CFL"
done

# ---------------------------------------------------------------------------
echo "== [S16-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-16.sh"
if [[ -x "$SELF" ]]; then
  pass "[S16-Z] sprint-16.sh is executable"
else
  fail "[S16-Z] sprint-16.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S16-Z] sprint-16.sh shebang is #!/bin/bash"
else
  fail "[S16-Z] sprint-16.sh shebang is #!/bin/bash"
fi
for sec in "S16-A" "S16-B" "S16-C" "S16-D" "S16-Z"; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S16-Z] [$sec] section header present"
  else
    fail "[S16-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
