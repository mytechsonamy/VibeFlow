#!/bin/bash
# Sprint 50 integration harness — consensus-gate honors the VF_SKIP_CONSENSUS_GATE
# escape hatch even when it's a command-prefix env var alongside another (e.g.
# `VF_SKIP_CONSENSUS_GATE=1 VF_ALLOW_PHASE_WRITE=1 bash -c …`). The env check only
# saw a single reliably-exported leading var, so the bypass "only worked as the
# sole leading var" — now the gate also matches the assignment in the command
# string, order- and count-independent.
#
# Sections:
#   [S50-A] gate parses the bypass from the command string
#   [S50-B] runtime — single / double / reversed bypass all allow; non-bypass blocks
#   [S50-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

GATE="$REPO_ROOT/hooks/scripts/consensus-gate.sh"

# ---------------------------------------------------------------------------
echo "== [S50-A] gate parses the bypass from the command string =="

assert_grep "[S50-A] env check (single reliably-exported var) still present" \
  'VF_SKIP_CONSENSUS_GATE:-.*== "1"' "$GATE"
assert_grep "[S50-A] also matches VF_SKIP in the command string" \
  'grep -qE .*VF_SKIP_CONSENSUS_GATE=\(1\|true\)' "$GATE"
assert_grep "[S50-A] documents the two-env-var case" \
  "alongside another|two leading assignments|order- and count-independent" "$GATE"

# ---------------------------------------------------------------------------
echo "== [S50-B] runtime — bypass is order- and count-independent =="

run_gate() {  # $1 = command string; echoes "allow" or "block"
  local cmd="$1" tdir in out rc
  tdir="$(mktemp -d)"
  mkdir -p "$tdir/.vibeflow/state"
  echo '{"primaryArtifact":"docs/x.md","requiredCommand":"/vibeflow:phase-runner"}' \
    > "$tdir/.vibeflow/state/consensus-needed.json"
  in="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  out="$( (cd "$tdir" && printf '%s' "$in" | bash "$GATE" 2>/dev/null) )"; rc=$?
  rm -rf "$tdir"
  if [[ "$rc" == "0" && "$out" == *'"continue":true'* ]]; then echo allow; else echo block; fi
}

[[ "$(run_gate "VF_SKIP_CONSENSUS_GATE=1 bash -c 'echo a'")" == "allow" ]] \
  && pass "[S50-B] single leading bypass → allow" || fail "[S50-B] single leading bypass → allow"
[[ "$(run_gate "VF_SKIP_CONSENSUS_GATE=1 VF_ALLOW_PHASE_WRITE=1 bash -c 'echo a'")" == "allow" ]] \
  && pass "[S50-B] double env-var bypass (VF_SKIP first) → allow" || fail "[S50-B] double env-var bypass (VF_SKIP first) → allow"
[[ "$(run_gate "VF_ALLOW_PHASE_WRITE=1 VF_SKIP_CONSENSUS_GATE=1 bash -c 'echo a'")" == "allow" ]] \
  && pass "[S50-B] reversed double env-var bypass → allow" || fail "[S50-B] reversed double env-var bypass → allow"
[[ "$(run_gate "jq '.x' file")" == "block" ]] \
  && pass "[S50-B] non-bypass command with armed marker → block (gate still works)" || fail "[S50-B] non-bypass command → block"
# A command that merely mentions the var in a string literal is NOT a prefix
# assignment — should still block (no accidental bypass).
[[ "$(run_gate "echo 'set VF_SKIP_CONSENSUS_GATE=1 in docs'")" == "block" ]] \
  && pass "[S50-B] var named inside a quoted echo arg does not bypass" || fail "[S50-B] quoted mention does not bypass"

# ---------------------------------------------------------------------------
echo "== [S50-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-50.sh"
assert_grep "[S50-Z] sprint-50.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S50-Z] covers [S50-A]" '\[S50-A\]' "$SELF"
assert_grep "[S50-Z] covers [S50-B]" '\[S50-B\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
