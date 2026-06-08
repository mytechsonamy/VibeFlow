#!/bin/bash
# Sprint 48 integration harness — sdlc_start_cycle engine reset backs the
# Sprint-42 multi-cycle lifecycle. Without it the engine stays pinned at the
# prior cycle's terminal phase (DEPLOYMENT) and phase-runner mismatches for the
# next increment.
#
# Sections:
#   [S48-A] engine: tool + method + ProjectState.cycle + unit test
#   [S48-B] skills: brownfield-intake resets the engine + phase-runner reconcile
#   [S48-C] docs/LIFECYCLE.md documents the engine reset
#   [S48-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

ENG="$REPO_ROOT/mcp-servers/sdlc-engine"
BI="$REPO_ROOT/skills/brownfield-intake/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
DOC="$REPO_ROOT/docs/LIFECYCLE.md"

# ---------------------------------------------------------------------------
echo "== [S48-A] engine: sdlc_start_cycle =="

assert_grep "[S48-A] tools.ts registers sdlc_start_cycle" 'name: "sdlc_start_cycle"' "$ENG/src/tools.ts"
assert_grep "[S48-A] StartCycleInput zod schema" "StartCycleInput = z.object" "$ENG/src/tools.ts"
assert_grep "[S48-A] engine.startCycle method" "async startCycle\(" "$ENG/src/engine.ts"
assert_grep "[S48-A] startCycle resets to the first phase" "currentPhase: this.registry.first\(\).id" "$ENG/src/engine.ts"
assert_grep "[S48-A] startCycle clears criteria" "satisfiedCriteria: \[\]" "$ENG/src/engine.ts"
assert_grep "[S48-A] startCycle clears lastConsensus" "lastConsensus: null" "$ENG/src/engine.ts"
assert_grep "[S48-A] startCycle bumps the cycle counter" 'cycle: \(base.cycle \?\? 1\) \+ 1' "$ENG/src/engine.ts"
assert_grep "[S48-A] ProjectState gains a cycle field" "readonly cycle\?: number" "$ENG/src/state/store.ts"
assert_grep "[S48-A] engine unit test covers startCycle" "startCycle resets to REQUIREMENTS" "$ENG/tests/engine.test.ts"
# Build the dist + run the engine unit tests live.
if (cd "$ENG" && npm run build >/dev/null 2>&1 && npm test >/tmp/s48_eng.log 2>&1); then
  pass "[S48-A] engine builds + all unit tests pass (incl. startCycle)"
else
  fail "[S48-A] engine builds + unit tests pass (see /tmp/s48_eng.log)"
fi
assert_grep "[S48-A] dist exposes sdlc_start_cycle (built)" "sdlc_start_cycle" "$ENG/dist/bundle.js"

# ---------------------------------------------------------------------------
echo "== [S48-B] skills wiring =="

assert_grep "[S48-B] brownfield-intake allowed-tools include sdlc_start_cycle" \
  "mcp__sdlc-engine__sdlc_start_cycle" "$BI"
assert_grep "[S48-B] brownfield-intake resets the engine on a new increment" \
  "Reset the SDLC engine|sdlc_start_cycle" "$BI"
assert_grep "[S48-B] brownfield-intake explains the mismatch it prevents" \
  "engine=DEPLOYMENT vs config=REQUIREMENTS|pinned at the .previous" "$BI"
assert_grep "[S48-B] phase-runner allowed-tools include sdlc_start_cycle" \
  "mcp__sdlc-engine__sdlc_start_cycle" "$RUNNER"
assert_grep "[S48-B] phase-runner Step 0 reconciles engine/lifecycle drift" \
  "Engine/lifecycle drift|engine \\*\\*ahead\\*\\*|reconcile before Step 1" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S48-C] docs =="

assert_grep "[S48-C] LIFECYCLE.md documents the two stores + reset" \
  "sdlc_start_cycle|two stores|kept in sync" "$DOC"
assert_grep "[S48-C] LIFECYCLE.md notes the engine would otherwise stall cycle-2" \
  "phase-mismatch|pinned at the previous cycle|cycle-2 stalled" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S48-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-48.sh"
assert_grep "[S48-Z] sprint-48.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S48-Z] covers [S48-A]" '\[S48-A\]' "$SELF"
assert_grep "[S48-Z] covers [S48-B]" '\[S48-B\]' "$SELF"
assert_grep "[S48-Z] covers [S48-C]" '\[S48-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
