#!/bin/bash
# design-guard test harness. Covers the VibeFlow bridge (record_audit.py) +
# the inert-without-a-project guarantees of the hook scripts.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILS=()
pass() { PASS=$((PASS+1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL+1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_eq() { local l="$1" e="$2" a="$3"; [[ "$e" == "$a" ]] && pass "$l" || fail "$l (expected=$e actual=$a)"; }

REC="$ROOT/scripts/record_audit.py"

echo "== record_audit.py — VibeFlow bridge =="

# 1. No-op outside a VibeFlow project: no file created, exit 0.
P="$(mktemp -d)"
OUT="$(CLAUDE_PROJECT_DIR="$P" python3 "$REC" SHIPPABLE --blockers 0 2>&1; echo "rc=$?")"
assert_eq "no-op outside VibeFlow → exit 0" "rc=0" "$(printf '%s' "$OUT" | tail -1)"
[[ ! -e "$P/.vibeflow" ]] && pass "no-op creates no .vibeflow dir" || fail "no-op created .vibeflow"
rm -rf "$P"

# 2. Inside a VibeFlow project: appends one valid design-guard-audit row.
P="$(mktemp -d)"; mkdir -p "$P/.vibeflow/state/consensus"
CLAUDE_PROJECT_DIR="$P" python3 "$REC" "FIXES REQUIRED" --blockers 2 --majors 3 --minors 1 --scope "budget screen" >/dev/null 2>&1
H="$P/.vibeflow/state/consensus/history.jsonl"
assert_eq "row appended (1 line)" "1" "$(wc -l < "$H" | tr -d ' ')"
assert_eq "type is design-guard-audit" "design-guard-audit" "$(jq -r '.type' "$H")"
assert_eq "space form 'FIXES REQUIRED' normalized" "FIXES_REQUIRED" "$(jq -r '.verdict' "$H")"
assert_eq "blockers captured" "2" "$(jq -r '.blockers' "$H")"
assert_eq "scope captured" "budget screen" "$(jq -r '.scope' "$H")"
assert_eq "source tagged" "design-auditor" "$(jq -r '.source' "$H")"
# A second audit appends, doesn't clobber.
CLAUDE_PROJECT_DIR="$P" python3 "$REC" SHIPPABLE >/dev/null 2>&1
assert_eq "second audit appends (2 lines)" "2" "$(wc -l < "$H" | tr -d ' ')"
assert_eq "latest row is SHIPPABLE" "SHIPPABLE" "$(jq -r '.verdict' "$H" | tail -1)"
rm -rf "$P"

# 3. Bad verdict → exit 1, nothing written.
P="$(mktemp -d)"; mkdir -p "$P/.vibeflow/state/consensus"
RC="$(CLAUDE_PROJECT_DIR="$P" python3 "$REC" MAYBE >/dev/null 2>&1; echo $?)"
assert_eq "invalid verdict → exit 1" "1" "$RC"
[[ ! -e "$P/.vibeflow/state/consensus/history.jsonl" ]] && pass "invalid verdict writes nothing" || fail "invalid verdict wrote a row"
rm -rf "$P"

echo "== hook scripts inert without a project =="
P="$(mktemp -d)"
for s in ui_lint stop_gate; do
  RC="$(cd "$P" && echo '{}' | CLAUDE_PLUGIN_ROOT="$ROOT" python3 "$ROOT/scripts/$s.py" >/dev/null 2>&1; echo $?)"
  assert_eq "$s.py inert (exit 0) in uninitialized project" "0" "$RC"
done
rm -rf "$P"

echo
echo "RESULTS: $PASS passed, $FAIL failed"
(( FAIL > 0 )) && { for f in "${FAILS[@]}"; do echo "  - $f"; done; exit 1; }
exit 0
