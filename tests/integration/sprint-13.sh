#!/bin/bash
# Sprint 13 integration harness — validates generic phase enforcement.
#
# Sections:
#   [S13-A] hooks/scripts/phase-policy.json structural sanity
#   [S13-B] hooks/scripts/phase-write-guard.sh surface
#   [S13-C] hooks/hooks.json wires the guard on PreToolUse/Write|Edit
#   [S13-D] init skill regression + four skills carry Phase Contracts
#   [S13-E] docs/PHASE-BOUNDARIES.md exists and documents every phase
#   [S13-F] docs/SPRINT-11.md + SPRINT-12.md + SPRINT-13.md exist
#   [S13-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S13-A] hooks/scripts/phase-policy.json structure =="

POLICY="$REPO_ROOT/hooks/scripts/phase-policy.json"
if [[ -f "$POLICY" ]]; then
  pass "[S13-A] phase-policy.json exists"
else
  fail "[S13-A] phase-policy.json exists"
fi

if command -v jq >/dev/null && jq empty "$POLICY" >/dev/null 2>&1; then
  pass "[S13-A] phase-policy.json is valid JSON"
else
  fail "[S13-A] phase-policy.json is valid JSON"
fi

for phase in REQUIREMENTS DESIGN ARCHITECTURE PLANNING DEVELOPMENT TESTING DEPLOYMENT; do
  if jq -e --arg p "$phase" '.phases[$p].allow | type == "array"' "$POLICY" >/dev/null 2>&1; then
    pass "[S13-A] phase $phase has .allow array"
  else
    fail "[S13-A] phase $phase has .allow array"
  fi
done

# Framework state must be writable in every phase — the guard must not
# ever block init, advance, etc. from updating .vibeflow/state. A phase
# satisfies this either by listing `.vibeflow/**` explicitly or by
# having the catchall `**` (only DEVELOPMENT today).
for phase in REQUIREMENTS DESIGN ARCHITECTURE PLANNING DEVELOPMENT TESTING DEPLOYMENT; do
  if jq -e --arg p "$phase" \
       '.phases[$p].allow | (index(".vibeflow/**") != null or index("**") != null)' \
       "$POLICY" >/dev/null 2>&1; then
    pass "[S13-A] $phase allows .vibeflow/** (explicit or via **)"
  else
    fail "[S13-A] $phase allows .vibeflow/** (explicit or via **)"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S13-B] hooks/scripts/phase-write-guard.sh surface =="

GUARD="$REPO_ROOT/hooks/scripts/phase-write-guard.sh"
if [[ -x "$GUARD" ]]; then
  pass "[S13-B] phase-write-guard.sh is executable"
else
  fail "[S13-B] phase-write-guard.sh is executable"
fi

if head -1 "$GUARD" | grep -q '^#!/bin/bash'; then
  pass "[S13-B] phase-write-guard.sh shebang is #!/bin/bash"
else
  fail "[S13-B] phase-write-guard.sh shebang is #!/bin/bash"
fi

if grep -q 'source "$SCRIPT_DIR/_lib.sh"' "$GUARD"; then
  pass "[S13-B] phase-write-guard.sh sources _lib.sh"
else
  fail "[S13-B] phase-write-guard.sh sources _lib.sh"
fi

if grep -q 'VF_ALLOW_PHASE_WRITE' "$GUARD"; then
  pass "[S13-B] phase-write-guard.sh honours VF_ALLOW_PHASE_WRITE"
else
  fail "[S13-B] phase-write-guard.sh honours VF_ALLOW_PHASE_WRITE"
fi

# ---------------------------------------------------------------------------
echo "== [S13-C] hooks/hooks.json wires the guard =="

HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[] | select(.command | contains("phase-write-guard.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "[S13-C] PreToolUse/Write|Edit entry points at phase-write-guard.sh"
else
  fail "[S13-C] PreToolUse/Write|Edit entry points at phase-write-guard.sh"
fi

# ---------------------------------------------------------------------------
echo "== [S13-D] init + four skills carry Phase Contract =="

INIT_MD="$REPO_ROOT/skills/init/SKILL.md"
if grep -q '## Phase Contract' "$INIT_MD"; then
  pass "[S13-D] init/SKILL.md has Phase Contract section"
else
  fail "[S13-D] init/SKILL.md has Phase Contract section"
fi

# Regression: the root bug removed its reference to codebase-explorer.
if ! grep -q 'codebase-explorer' "$INIT_MD"; then
  pass "[S13-D] init/SKILL.md no longer invokes codebase-explorer (regression pin)"
else
  fail "[S13-D] init/SKILL.md no longer invokes codebase-explorer (regression pin)"
fi

# Regression: Sprint 11-E legacy 'mode: solo/team' prompt was stale;
# Sprint 13-D removed it. Only the historical note about removal is
# allowed in the skill body.
if ! grep -qE '^\s*"mode"\s*:' "$INIT_MD"; then
  pass "[S13-D] init/SKILL.md config template no longer carries 'mode' key"
else
  fail "[S13-D] init/SKILL.md config template no longer carries 'mode' key"
fi

for skill in component-test-writer release-decision-engine test-strategy-planner coverage-analyzer; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  if grep -q '## Phase Contract' "$f"; then
    pass "[S13-D] $skill has Phase Contract"
  else
    fail "[S13-D] $skill has Phase Contract"
  fi
done

# Skill phase-policy registry exists and covers at least the critical 5.
SKILL_POLICY="$REPO_ROOT/skills/phase-policy.json"
if [[ -f "$SKILL_POLICY" ]] && jq empty "$SKILL_POLICY" >/dev/null 2>&1; then
  pass "[S13-D] skills/phase-policy.json exists + valid JSON"
else
  fail "[S13-D] skills/phase-policy.json exists + valid JSON"
fi
for skill in init component-test-writer release-decision-engine test-strategy-planner coverage-analyzer; do
  if jq -e --arg s "$skill" '.skills[$s] != null' "$SKILL_POLICY" >/dev/null 2>&1; then
    pass "[S13-D] skills/phase-policy.json covers $skill"
  else
    fail "[S13-D] skills/phase-policy.json covers $skill"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S13-E] docs/PHASE-BOUNDARIES.md =="

PB_DOC="$REPO_ROOT/docs/PHASE-BOUNDARIES.md"
if [[ -f "$PB_DOC" ]]; then
  pass "[S13-E] PHASE-BOUNDARIES.md exists"
else
  fail "[S13-E] PHASE-BOUNDARIES.md exists"
fi

for phase in REQUIREMENTS DESIGN ARCHITECTURE PLANNING DEVELOPMENT TESTING DEPLOYMENT; do
  if grep -q "$phase" "$PB_DOC"; then
    pass "[S13-E] PHASE-BOUNDARIES.md mentions $phase"
  else
    fail "[S13-E] PHASE-BOUNDARIES.md mentions $phase"
  fi
done

if grep -q 'VF_ALLOW_PHASE_WRITE' "$PB_DOC"; then
  pass "[S13-E] PHASE-BOUNDARIES.md documents the escape hatch"
else
  fail "[S13-E] PHASE-BOUNDARIES.md documents the escape hatch"
fi

# ---------------------------------------------------------------------------
echo "== [S13-F] retrospective sprint docs =="

for doc in SPRINT-11.md SPRINT-12.md SPRINT-13.md; do
  if [[ -f "$REPO_ROOT/docs/$doc" ]]; then
    pass "[S13-F] docs/$doc exists"
  else
    fail "[S13-F] docs/$doc exists"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S13-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-13.sh"
if [[ -x "$SELF" ]]; then
  pass "[S13-Z] sprint-13.sh is executable"
else
  fail "[S13-Z] sprint-13.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S13-Z] sprint-13.sh shebang is #!/bin/bash"
else
  fail "[S13-Z] sprint-13.sh shebang is #!/bin/bash"
fi
for sec in "S13-A" "S13-B" "S13-C" "S13-D" "S13-E" "S13-F" "S13-Z"; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S13-Z] [$sec] section header present"
  else
    fail "[S13-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
