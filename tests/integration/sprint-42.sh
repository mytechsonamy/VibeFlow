#!/bin/bash
# Sprint 42 integration harness — project lifecycle (cycles / resume / increments).
# A paused greenfield project must RESUME, not be re-onboarded or mis-read as
# brownfield. Each cycle = one branch/PR; a completed cycle starts a new increment.
#
# Sections:
#   [S42-A] onboard resume-guard + opens cycle-1
#   [S42-B] phase-runner lifecycle (resume vs new increment) + DEPLOYMENT closes cycle
#   [S42-C] brownfield-intake opens an increment cycle
#   [S42-D] docs/LIFECYCLE.md
#   [S42-E] runtime — resume-vs-new routing from lifecycle.json
#   [S42-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

ONB="$REPO_ROOT/skills/onboard/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
BI="$REPO_ROOT/skills/brownfield-intake/SKILL.md"
DOC="$REPO_ROOT/docs/LIFECYCLE.md"

# ---------------------------------------------------------------------------
echo "== [S42-A] onboard resume-guard + opens cycle-1 =="

assert_grep "[S42-A] onboard has a Step 0 resume-guard" "Step 0: Already onboarded|Resume, don't re-onboard" "$ONB"
assert_grep "[S42-A] guard keys off lifecycle.json, not file presence" \
  "lifecycle\.json|file presence is not the signal|lifecycle state" "$ONB"
assert_grep "[S42-A] in-progress cycle → resume via phase-runner" \
  "in-progress.*resume|Resuming|▶ Next: /vibeflow:phase-runner" "$ONB"
assert_grep "[S42-A] completed cycle → new increment via brownfield-intake" \
  "completed.*increment|new increment|▶ Next: /vibeflow:brownfield-intake" "$ONB"
assert_grep "[S42-A] explicitly warns greenfield-with-source is NOT brownfield" \
  "greenfield project that has reached DEVELOPMENT|file presence is not the signal" "$ONB"
assert_grep "[S42-A] Step 4b writes lifecycle.json cycle-1" \
  "lifecycle.json|cycle-1" "$ONB"
assert_grep "[S42-A] cycle-1 kind is initial + in-progress" \
  '"kind": "initial"' "$ONB"

# ---------------------------------------------------------------------------
echo "== [S42-B] phase-runner lifecycle + cycle close =="

assert_grep "[S42-B] phase-runner Step 0 reads lifecycle" "Step 0: Lifecycle|lifecycle\.json" "$RUNNER"
assert_grep "[S42-B] in-progress → resume (greenfield-paused case)" \
  "in-progress.*resume|greenfield-paused-and-resumed" "$RUNNER"
assert_grep "[S42-B] completed → new increment on a fresh branch" \
  "git checkout -b increment/|Start the next increment" "$RUNNER"
assert_grep "[S42-B] DEPLOYMENT closes the cycle on GO" \
  "DEPLOYMENT closes the cycle|currentCycle.status = .completed|shipped — DEPLOYMENT GO" "$RUNNER"
assert_grep "[S42-B] does NOT close on CONDITIONAL/BLOCKED" \
  "CONDITIONAL/BLOCKED|don't mark a cycle complete" "$RUNNER"
assert_grep "[S42-B] one cycle = one branch / PR (track-and-breadcrumb)" \
  "one branch / one PR|track-and-breadcrumb|one branch / PR" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S42-C] brownfield-intake opens an increment cycle =="

assert_grep "[S42-C] brownfield-intake opens a new increment cycle" \
  "lifecycle cycle|open a \\*\\*new\\*\\* cycle|kind.*increment" "$BI"
assert_grep "[S42-C] increment cycle is kind=increment" '"kind": "increment"' "$BI"
assert_grep "[S42-C] cycle-1 brownfield start reuses the open initial cycle" \
  "still-open .initial. cycle|don't open a second cycle" "$BI"

# ---------------------------------------------------------------------------
echo "== [S42-D] docs/LIFECYCLE.md =="

[[ -f "$DOC" ]] && pass "[S42-D] docs/LIFECYCLE.md exists" || fail "[S42-D] docs/LIFECYCLE.md exists"
assert_grep "[S42-D] documents cycles (initial vs increment)" "initial.*increment|Cycle 1|increment" "$DOC"
assert_grep "[S42-D] documents the resume-vs-new state machine" "resume|state machine" "$DOC"
assert_grep "[S42-D] documents one cycle = one branch/PR" "one branch / one PR|one branch/PR" "$DOC"
assert_grep "[S42-D] explains resume != brownfield" "misread as brownfield" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S42-E] runtime — routing from lifecycle.json =="

route() {  # mirrors the Step-0 decision
  local f="$1"
  [[ -f "$f" ]] || { echo "ONBOARD"; return; }
  case "$(jq -r '.currentCycle.status' "$f" 2>/dev/null)" in
    in-progress) echo "RESUME" ;;
    completed)   echo "NEW-INCREMENT" ;;
    *)           echo "BACKFILL" ;;
  esac
}
T="$(mktemp -d)"
# no lifecycle → onboard
[[ "$(route "$T/none.json")" == "ONBOARD" ]] && pass "[S42-E] no lifecycle → ONBOARD" || fail "[S42-E] no lifecycle → ONBOARD"
# in-progress → resume (the greenfield-paused case)
printf '{"currentCycle":{"status":"in-progress"}}' > "$T/ip.json"
[[ "$(route "$T/ip.json")" == "RESUME" ]] && pass "[S42-E] in-progress → RESUME (paused greenfield resumes)" || fail "[S42-E] in-progress → RESUME"
# completed → new increment
printf '{"currentCycle":{"status":"completed"}}' > "$T/done.json"
[[ "$(route "$T/done.json")" == "NEW-INCREMENT" ]] && pass "[S42-E] completed → NEW-INCREMENT" || fail "[S42-E] completed → NEW-INCREMENT"
rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S42-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-42.sh"
assert_grep "[S42-Z] sprint-42.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S42-Z] covers [S42-A]" '\[S42-A\]' "$SELF"
assert_grep "[S42-Z] covers [S42-B]" '\[S42-B\]' "$SELF"
assert_grep "[S42-Z] covers [S42-E]" '\[S42-E\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
