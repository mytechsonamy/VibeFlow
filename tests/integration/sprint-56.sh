#!/bin/bash
# Sprint 56 integration harness — phase-runner setup no longer trips the
# consensus-gate. An analyzer often arms consensus-needed.json right before
# phase-runner runs; phase-runner is the legitimate drainer, but its read-only
# setup (lifecycle/state/git status/the UI readers) tripped the gate. Now: read
# state via the Read tool + MCP (ungated), and the gate allowlists VibeFlow's
# read-only readers + git inspection (they don't bypass consensus).
#
# Sections:
#   [S56-A] gate allowlists read-only readers + git status/rev-parse (+ runtime)
#   [S56-B] phase-runner Step 0 reads state via Read/MCP, not Bash/VF_SKIP
#   [S56-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

GATE="$REPO_ROOT/hooks/scripts/consensus-gate.sh"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S56-A] gate allowlists read-only inspection =="

assert_grep "[S56-A] allowlists ui-verification-debt.sh" '\*ui-verification-debt\.sh\*\)' "$GATE"
assert_grep "[S56-A] allowlists ui-styling-check.sh" '\*ui-styling-check\.sh\*\)' "$GATE"
assert_grep "[S56-A] allowlists loop-audit.sh" '\*loop-audit\.sh\*\)' "$GATE"
assert_grep "[S56-A] allowlists git status (read-only)" 'git status' "$GATE"
assert_grep "[S56-A] allowlists git rev-parse (read-only)" 'git rev-parse' "$GATE"
assert_grep "[S56-A] documents these only inspect (don't bypass consensus)" \
  "only inspect|read-only|don.t .move past." "$GATE"

# Runtime: armed marker — read-only allow, writes block.
gate_decision() {  # $1 = command → allow|block
  local cmd="$1" tdir in out rc
  tdir="$(mktemp -d)"; mkdir -p "$tdir/.vibeflow/state"
  echo '{"primaryArtifact":"docs/x.md","requiredCommand":"/vibeflow:phase-runner"}' \
    > "$tdir/.vibeflow/state/consensus-needed.json"
  in="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  out="$( (cd "$tdir" && printf '%s' "$in" | bash "$GATE" 2>/dev/null) )"; rc=$?
  rm -rf "$tdir"
  [[ "$rc" == 0 && "$out" == *'"continue":true'* ]] && echo allow || echo block
}

[[ "$(gate_decision 'git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git status --porcelain | head')" == "allow" ]] \
  && pass "[S56-A] git rev-parse && git status → allow" || fail "[S56-A] git status → allow"
[[ "$(gate_decision 'bash hooks/scripts/ui-verification-debt.sh .')" == "allow" ]] \
  && pass "[S56-A] ui-verification-debt reader → allow" || fail "[S56-A] ui-verification-debt → allow"
[[ "$(gate_decision 'bash hooks/scripts/ui-styling-check.sh .')" == "allow" ]] \
  && pass "[S56-A] ui-styling-check reader → allow" || fail "[S56-A] ui-styling-check → allow"
[[ "$(gate_decision 'bash hooks/scripts/consensus-run.sh m.json')" == "allow" ]] \
  && pass "[S56-A] consensus-run.sh (drainer) → allow (unchanged)" || fail "[S56-A] consensus-run.sh → allow"
[[ "$(gate_decision 'echo hi > src/foo.ts')" == "block" ]] \
  && pass "[S56-A] a write (> src/foo.ts) → still BLOCK (gate intact)" || fail "[S56-A] write → block"
[[ "$(gate_decision 'npm run build')" == "block" ]] \
  && pass "[S56-A] forward work (npm run build) → still BLOCK" || fail "[S56-A] forward work → block"

# ---------------------------------------------------------------------------
echo "== [S56-B] phase-runner reads setup state ungated =="

assert_grep "[S56-B] Step 0 says gather setup state via Read tool + MCP, not Bash" \
  "Read tool \+ MCP, NOT Bash|with the \\*\\*Read tool\\*\\*" "$RUNNER"
assert_grep "[S56-B] names the marker-armed-by-analyzer scenario" \
  "prd-quality-analyzer. often armed|consensus-needed.json. just before" "$RUNNER"
assert_grep "[S56-B] says don't reach for VF_SKIP just to read state" \
  "not.*reach for .VF_SKIP_CONSENSUS_GATE=1. just to read|switch tools" "$RUNNER"
assert_grep "[S56-B] lifecycle.json read with the Read tool" \
  "lifecycle.json. with the \\*\\*Read tool\\*\\*" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S56-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-56.sh"
assert_grep "[S56-Z] sprint-56.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S56-Z] covers [S56-A]" '\[S56-A\]' "$SELF"
assert_grep "[S56-Z] covers [S56-B]" '\[S56-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
