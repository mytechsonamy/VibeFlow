#!/bin/bash
# VibeFlow hook tests.
# Exercises every hook with fixture stdin + a synthetic vibeflow.config.json
# and state.db built on the fly. Run from anywhere:
#   bash hooks/tests/run.sh
#
# Exits 0 when every assertion passes, 1 otherwise. Uses VIBEFLOW_CWD to
# point each hook at a throwaway temp project so nothing touches the real
# repo state.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO_ROOT/hooks/scripts"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected=$expected actual=$actual)"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (no '$needle' in: $haystack)"
  fi
}

make_project() {
  local phase="$1" mode="${2:-solo}"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
  cat > "$dir/vibeflow.config.json" <<EOF
{
  "project": "testproj",
  "mode": "$mode",
  "domain": "general",
  "currentPhase": "$phase"
}
EOF
  mkdir -p "$dir/.vibeflow"
  sqlite3 "$dir/.vibeflow/state.db" <<SQL
CREATE TABLE project_state (
  project_id TEXT PRIMARY KEY,
  current_phase TEXT NOT NULL,
  satisfied_criteria TEXT NOT NULL,
  last_consensus TEXT,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL
);
INSERT INTO project_state VALUES (
  'testproj',
  '$phase',
  '["prd.approved"]',
  '{"phase":"REQUIREMENTS","status":"APPROVED","agreement":0.95,"criticalIssues":0,"recordedAt":"2026-04-01T00:00:00Z"}',
  '2026-04-01T00:00:00Z',
  2
);
SQL
  echo "$dir"
}

cleanup() {
  [[ -n "${DIR:-}" && -d "$DIR" ]] && rm -rf "$DIR"
}
trap cleanup EXIT

echo "== commit-guard.sh =="

# Phase block: REQUIREMENTS should block the commit.
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"feat: add thing\""}}'
OUT="$(echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" 2>&1 || true)"
RC=$?
# shellcheck disable=SC2181
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "blocks commit in REQUIREMENTS phase (exit 2)" "2" "$RC"
assert_contains "phase block mentions REQUIREMENTS" "REQUIREMENTS" "$OUT"
rm -rf "$DIR"

# Phase OK, bad format.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"oops no prefix\""}}'
OUT="$(echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" 2>&1 || true)"
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "blocks malformed commit message (exit 2)" "2" "$RC"
assert_contains "format error mentions conventional" "conventional" "$OUT"
rm -rf "$DIR"

# Phase OK, good format.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"feat(hooks): implement guard\""}}'
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "allows conformant commit (exit 0)" "0" "$RC"
rm -rf "$DIR"

# Non-git command passes through even in REQUIREMENTS.
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"ls -la"}}'
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "non-git command passes through (exit 0)" "0" "$RC"
rm -rf "$DIR"

echo "== load-sdlc-context.sh =="

DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
assert_contains "emits phase from state.db" "phase=DEVELOPMENT" "$OUT"
assert_contains "emits last_consensus" "last_consensus=APPROVED" "$OUT"
assert_contains "emits satisfied criteria count" "satisfied_criteria=1" "$OUT"
rm -rf "$DIR"

# No config: graceful message.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
assert_contains "missing config produces init hint" "vibeflow:init" "$OUT"
rm -rf "$DIR"

echo "== post-edit.sh =="

DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"/tmp/project/src/foo.ts"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
LOG="$DIR/.vibeflow/traces/changed-files.log"
assert_contains "log exists after edit" "src/foo.ts" "$(cat "$LOG" 2>/dev/null || echo missing)"

# Docs are skipped.
INPUT='{"tool_input":{"file_path":"/tmp/project/README.md"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq "md edit is not logged" "1" "$COUNT"

# Edits inside .vibeflow/ are skipped.
INPUT='{"tool_input":{"file_path":"/tmp/project/.vibeflow/state/foo.json"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq ".vibeflow edit is not logged" "1" "$COUNT"
rm -rf "$DIR"

echo "== trigger-ai-review.sh =="

# Solo mode: no marker even with lots of changes.
DIR="$(make_project DEVELOPMENT solo)"
export VIBEFLOW_CWD="$DIR"
bash "$SCRIPTS/trigger-ai-review.sh" < /dev/null >/dev/null 2>&1
[[ ! -f "$DIR/.vibeflow/state/review-pending.json" ]] \
  && pass "solo mode writes no review marker" \
  || fail "solo mode writes no review marker"
rm -rf "$DIR"

# Team mode inside a git repo with a small diff → below threshold → no marker.
DIR="$(make_project DEVELOPMENT team)"
export VIBEFLOW_CWD="$DIR"
(
  cd "$DIR"
  git init -q
  git config user.email test@example.com
  git config user.name test
  echo "x" > small.txt
  git add small.txt
  git commit -q -m "feat: small"
)
bash "$SCRIPTS/trigger-ai-review.sh" < /dev/null >/dev/null 2>&1
[[ ! -f "$DIR/.vibeflow/state/review-pending.json" ]] \
  && pass "small diff below threshold writes no marker" \
  || fail "small diff below threshold writes no marker"

# Big commit → marker.
(
  cd "$DIR"
  seq 1 80 > big.txt
  git add big.txt
  git commit -q -m "feat: big"
)
bash "$SCRIPTS/trigger-ai-review.sh" < /dev/null >/dev/null 2>&1
MARKER="$DIR/.vibeflow/state/review-pending.json"
[[ -f "$MARKER" ]] \
  && pass "large diff writes review marker" \
  || fail "large diff writes review marker"
if [[ -f "$MARKER" ]]; then
  LINES="$(jq -r '.changedLines' "$MARKER")"
  assert_eq "marker records 80 changed lines" "80" "$LINES"
fi
rm -rf "$DIR"

echo "== test-optimizer.sh =="

DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
# Build a fake src/test layout under DIR.
mkdir -p "$DIR/src" "$DIR/src/__tests__"
touch "$DIR/src/foo.ts" "$DIR/src/foo.test.ts" "$DIR/src/bar.ts"
# Seed a changed-files log.
mkdir -p "$DIR/.vibeflow/traces"
printf '2026-04-12T00:00:00Z\tDEVELOPMENT\t%s\n' "$DIR/src/foo.ts" "$DIR/src/bar.ts" \
  > "$DIR/.vibeflow/traces/changed-files.log"

bash "$SCRIPTS/test-optimizer.sh" < /dev/null >/dev/null
HINT="$DIR/.vibeflow/state/next-test-hint.json"
[[ -f "$HINT" ]] && pass "hint file written" || fail "hint file written"
if [[ -f "$HINT" ]]; then
  COUNT="$(jq -r '.count' "$HINT")"
  assert_eq "hint contains 1 candidate (only foo has a test)" "1" "$COUNT"
  CANDIDATE="$(jq -r '.candidates[0]' "$HINT")"
  assert_contains "candidate is the foo test" "foo.test.ts" "$CANDIDATE"
fi
rm -rf "$DIR"

echo "== compact-recovery.sh =="

DIR="$(make_project DESIGN)"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "snapshot mentions phase" "phase=DESIGN" "$OUT"
assert_contains "snapshot mentions criteria" "prd.approved" "$OUT"
rm -rf "$DIR"

echo "== consensus-aggregator.sh =="

# Solo mode quorum = 1: single APPROVED review finalizes instantly.
DIR="$(make_project DEVELOPMENT solo)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"session_id":"s1","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
echo "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
VERDICT_FILE="$DIR/.vibeflow/state/consensus/s1.verdict.json"
[[ -f "$VERDICT_FILE" ]] && pass "solo verdict file written after 1 review" \
  || fail "solo verdict file written after 1 review"
if [[ -f "$VERDICT_FILE" ]]; then
  STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  assert_eq "solo single APPROVED review → APPROVED" "APPROVED" "$STATUS"
fi
rm -rf "$DIR"

# Team mode quorum = 3; 2 APPROVED + 1 REJECTED → criticalIssues decides.
DIR="$(make_project DEVELOPMENT team)"
export VIBEFLOW_CWD="$DIR"
for verdict_input in \
  '{"session_id":"s2","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}' \
  '{"session_id":"s2","subagent_type":"chatgpt-reviewer","tool_response":{"content":[{"text":"Final: APPROVED\ncritical issues: 0"}]}}' \
  '{"session_id":"s2","subagent_type":"gemini-reviewer","tool_response":{"content":[{"text":"Verdict: REJECTED\ncritical issues: 2"}]}}'
do
  echo "$verdict_input" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
done
VERDICT_FILE="$DIR/.vibeflow/state/consensus/s2.verdict.json"
[[ -f "$VERDICT_FILE" ]] && pass "team verdict file written after 3 reviews" \
  || fail "team verdict file written after 3 reviews"
if [[ -f "$VERDICT_FILE" ]]; then
  STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  # criticalTotal = 2 → REJECTED regardless of agreement.
  assert_eq "2 critical issues → REJECTED" "REJECTED" "$STATUS"
fi
rm -rf "$DIR"

unset VIBEFLOW_CWD

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
