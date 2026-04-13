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

# Merge commit (git's built-in format) passes the conventional-commit check.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"Merge branch '\''feat/foo'\'' into main\""}}'
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "commit-guard: allows Merge-prefixed commit (exit 0)" "0" "$RC"
rm -rf "$DIR"

# Revert commit (git's built-in format) passes the conventional-commit check.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"Revert \\\"feat: add thing\\\"\""}}'
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "commit-guard: allows Revert-prefixed commit (exit 0)" "0" "$RC"
rm -rf "$DIR"

# Command substitution in the message — pass through; the real commit
# text is unknowable until the shell expands $(...).
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<EOF\nfeat: dynamic\nEOF\n)\""}}'
echo "$INPUT" | bash "$SCRIPTS/commit-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "commit-guard: passes through command substitution (exit 0)" "0" "$RC"
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

# Degraded state: config exists but state.db is missing → surface a
# "(degraded: ... phase read from config)" note so the model knows the
# phase line is approximate. We write a vibeflow.config.json but skip
# the sqlite3 seed.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"degraded","mode":"solo","domain":"general","currentPhase":"DESIGN"}
EOF
mkdir -p "$DIR/.vibeflow"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
assert_contains "degraded note when state.db missing" "degraded" "$OUT"
assert_contains "degraded note names state.db" "state.db" "$OUT"
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

# .env files and .DS_Store are skipped.
INPUT='{"tool_input":{"file_path":"/tmp/project/.env"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq ".env edit is not logged" "1" "$COUNT"

INPUT='{"tool_input":{"file_path":"/tmp/project/src/.DS_Store"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq ".DS_Store edit is not logged" "1" "$COUNT"

# Editor swap / backup files are skipped.
INPUT='{"tool_input":{"file_path":"/tmp/project/src/foo.ts.swp"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq ".swp edit is not logged" "1" "$COUNT"

INPUT='{"tool_input":{"file_path":"/tmp/project/src/foo.ts~"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq "backup~ edit is not logged" "1" "$COUNT"

# Debounce: a second edit to the same file within the debounce window
# (5s) must not produce a second row. The log has 1 entry before; 1
# after the immediate re-edit; the edit of a DIFFERENT file still
# increments normally.
INPUT='{"tool_input":{"file_path":"/tmp/project/src/foo.ts"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq "debounce suppresses same-file rapid re-edit" "1" "$COUNT"

INPUT='{"tool_input":{"file_path":"/tmp/project/src/bar.ts"}}'
echo "$INPUT" | bash "$SCRIPTS/post-edit.sh" >/dev/null
COUNT="$(wc -l < "$LOG" | tr -d ' ')"
assert_eq "different-file edit still logs" "2" "$COUNT"

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

# Rate limit: a second large commit within 5 minutes MUST NOT overwrite
# the existing pending marker. We record the original SHA, fire a fresh
# big commit, and assert the marker still points at the original SHA.
ORIGINAL_SHA="$(jq -r '.commitSha' "$MARKER")"
(
  cd "$DIR"
  seq 100 180 > bigger.txt
  git add bigger.txt
  git commit -q -m "feat: bigger"
)
bash "$SCRIPTS/trigger-ai-review.sh" < /dev/null >/dev/null 2>&1
RATE_LIMITED_SHA="$(jq -r '.commitSha' "$MARKER")"
assert_eq "rate limit keeps original marker within 5 min" "$ORIGINAL_SHA" "$RATE_LIMITED_SHA"

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

# Cache: after the first run, test-mapping.cache.json exists and
# records the resolved test path keyed by the source file.
CACHE="$DIR/.vibeflow/state/test-mapping.cache.json"
[[ -f "$CACHE" ]] && pass "test-optimizer writes mapping cache" \
  || fail "test-optimizer writes mapping cache"
if [[ -f "$CACHE" ]]; then
  CACHED_TEST="$(jq -r --arg s "$DIR/src/foo.ts" '.[$s].test // empty' "$CACHE")"
  assert_contains "cache records foo → foo.test.ts mapping" "foo.test.ts" "$CACHED_TEST"
fi

# Cache reuse: a second run with the same source files produces the
# same hint without having to re-stat every try[] path. The contract
# we actually test is "cache still has the entry and hint is
# consistent" — perf is not testable from bash, but identity is.
bash "$SCRIPTS/test-optimizer.sh" < /dev/null >/dev/null
[[ -f "$HINT" ]] && pass "second run still emits hint" \
  || fail "second run still emits hint"
COUNT2="$(jq -r '.count' "$HINT")"
assert_eq "second run hint has same candidate count" "1" "$COUNT2"

# Cache invalidation: touch the source file so its mtime advances past
# the cached mtime, then re-run. The cache entry must be refreshed to
# the new mtime (not still pointing at the old value).
sleep 1                                   # ensure mtime granularity
touch "$DIR/src/foo.ts"
NEW_MTIME="$(stat -f '%m' "$DIR/src/foo.ts" 2>/dev/null || stat -c '%Y' "$DIR/src/foo.ts")"
bash "$SCRIPTS/test-optimizer.sh" < /dev/null >/dev/null
CACHED_MTIME="$(jq -r --arg s "$DIR/src/foo.ts" '.[$s].mtime // empty' "$CACHE")"
assert_eq "cache invalidates on source mtime change" "$NEW_MTIME" "$CACHED_MTIME"

rm -rf "$DIR"

echo "== compact-recovery.sh =="

DIR="$(make_project DESIGN)"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "snapshot mentions phase" "phase=DESIGN" "$OUT"
assert_contains "snapshot mentions criteria" "prd.approved" "$OUT"
rm -rf "$DIR"

# Integrity check: config.currentPhase disagrees with state.db. The
# config says REQUIREMENTS but the state.db (via make_project) says
# DEVELOPMENT. The snapshot must surface "state integrity degraded".
DIR="$(make_project DEVELOPMENT)"
# Rewrite the config to disagree with the db.
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"testproj","mode":"solo","domain":"general","currentPhase":"REQUIREMENTS"}
EOF
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "integrity degraded when config vs db disagree" "state integrity degraded" "$OUT"
assert_contains "integrity reason names both phases" "disagrees" "$OUT"
rm -rf "$DIR"

# Integrity check: state.db missing → snapshot reports it.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"noDB","mode":"solo","domain":"general","currentPhase":"DESIGN"}
EOF
mkdir -p "$DIR/.vibeflow"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "integrity reports missing state.db" "state.db missing" "$OUT"
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

# Timeout: team mode expects 3 reviewers, only 1 shows up, but the
# session log's oldest entry is > 600s old. The aggregator must
# force-finalize with timeout=true and demote APPROVED → NEEDS_REVISION
# (partial quorum cannot ship an APPROVED verdict). We pre-seed the
# session log with an old APPROVED entry, then fire a fresh APPROVED
# through the hook to trigger evaluation.
DIR="$(make_project DEVELOPMENT team)"
export VIBEFLOW_CWD="$DIR"
CONS_DIR="$DIR/.vibeflow/state/consensus"
mkdir -p "$CONS_DIR"
OLD_TS="2020-01-01T00:00:00Z"
printf '{"recordedAt":"%s","reviewer":"claude-reviewer","verdict":"APPROVED","criticalIssues":0}\n' \
  "$OLD_TS" > "$CONS_DIR/s3.jsonl"
INPUT='{"session_id":"s3","subagent_type":"chatgpt-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
echo "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
TIMEOUT_VERDICT="$CONS_DIR/s3.verdict.json"
[[ -f "$TIMEOUT_VERDICT" ]] \
  && pass "timeout force-finalizes partial quorum" \
  || fail "timeout force-finalizes partial quorum"
if [[ -f "$TIMEOUT_VERDICT" ]]; then
  TIMED="$(jq -r '.timeout' "$TIMEOUT_VERDICT")"
  assert_eq "timeout flag set on force-finalized verdict" "true" "$TIMED"
  STATUS="$(jq -r '.status' "$TIMEOUT_VERDICT")"
  assert_eq "timed-out APPROVED demoted to NEEDS_REVISION" "NEEDS_REVISION" "$STATUS"
  RECEIVED="$(jq -r '.receivedReviewers' "$TIMEOUT_VERDICT")"
  assert_eq "timeout records received reviewer count" "2" "$RECEIVED"
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
