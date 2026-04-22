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
  # Sprint 14-C: `mode` argument is accepted for backwards compatibility
  # with older callers in this file, but it is never written into the
  # synthesised config. Callers that need to exercise quorum behaviour
  # now write `consensus.quorum` explicitly after fixture creation.
  local phase="$1" _legacy_mode="${2:-}"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
  cat > "$dir/vibeflow.config.json" <<EOF
{
  "project": "testproj",
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

# Output budget (S4-08 memory footprint guard): the SessionStart hook
# is injected into Claude Code as a system note, so it competes for
# context budget. Keep it under 250 characters so even with multiple
# satisfied criteria the line stays compact.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
LSC_OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
LSC_LEN="${#LSC_OUT}"
if (( LSC_LEN <= 250 )); then
  pass "load-sdlc-context output stays under 250 char budget (got $LSC_LEN)"
else
  fail "load-sdlc-context output exceeds 250 char budget (got $LSC_LEN)"
fi
rm -rf "$DIR"

# Degraded state: config exists but state.db is missing → surface a
# "(degraded: ... phase read from config)" note so the model knows the
# phase line is approximate. We write a vibeflow.config.json but skip
# the sqlite3 seed.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"degraded","domain":"general","currentPhase":"DESIGN"}
EOF
mkdir -p "$DIR/.vibeflow"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
assert_contains "degraded note when no project.json" "degraded" "$OUT"
assert_contains "degraded note names project.json" "project.json" "$OUT"
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
# Sprint 9 — portable mtime read. BSD stat (macOS) accepts `-f '%m'`;
# GNU stat (Linux) accepts `-c '%Y'`. The old `stat -f '%m' || stat -c
# '%Y'` relied on GNU stat failing cleanly on `-f '%m'`, but GNU stat
# actually RE-interprets the argument as a filesystem-info request,
# prints filesystem stats to stdout, then exits non-zero — both sides
# of `||` land in the command-substitution capture. Probe once + pick
# the right invocation.
if stat -f '%m' "$DIR/src/foo.ts" >/dev/null 2>&1; then
  NEW_MTIME="$(stat -f '%m' "$DIR/src/foo.ts")"
else
  NEW_MTIME="$(stat -c '%Y' "$DIR/src/foo.ts")"
fi
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

# Output budget (S4-08 memory footprint guard): the compact-recovery
# snapshot can grow with review notes + integrity warnings + criteria
# list, but it must stay under 800 chars so re-injecting it after a
# compact doesn't bloat the recovered context.
CR_LEN="${#OUT}"
if (( CR_LEN <= 800 )); then
  pass "compact-recovery output stays under 800 char budget (got $CR_LEN)"
else
  fail "compact-recovery output exceeds 800 char budget (got $CR_LEN)"
fi
rm -rf "$DIR"

# Integrity check: config.currentPhase disagrees with state.db. The
# config says REQUIREMENTS but the state.db (via make_project) says
# DEVELOPMENT. The snapshot must surface "state integrity degraded".
DIR="$(make_project DEVELOPMENT)"
# Rewrite the config to disagree with the db.
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"testproj","domain":"general","currentPhase":"REQUIREMENTS"}
EOF
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "integrity degraded when config vs db disagree" "state integrity degraded" "$OUT"
assert_contains "integrity reason names both phases" "disagrees" "$OUT"
rm -rf "$DIR"

# Integrity check: state.db missing → snapshot reports it.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<'EOF'
{"project":"noDB","domain":"general","currentPhase":"DESIGN"}
EOF
mkdir -p "$DIR/.vibeflow"
export VIBEFLOW_CWD="$DIR"
OUT="$(bash "$SCRIPTS/compact-recovery.sh")"
assert_contains "integrity reports missing state.db" "state.db missing" "$OUT"
rm -rf "$DIR"

echo "== consensus-aggregator.sh =="

# Sprint 14-A: quorum is driven by CLI availability + optional
# consensus.quorum config override. Tests set the override explicitly
# so the assertion doesn't depend on whether codex/gemini CLIs are on
# the test host's PATH.

# Solo-style flow — quorum = 1, single APPROVED review finalizes.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
# Override quorum to 1 explicitly.
tmp_cfg="$DIR/vibeflow.config.json.tmp"
jq '. + {consensus: {quorum: 1}}' "$DIR/vibeflow.config.json" > "$tmp_cfg" \
  && mv "$tmp_cfg" "$DIR/vibeflow.config.json"
INPUT='{"session_id":"s1","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
printf '%s' "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
VERDICT_FILE="$DIR/.vibeflow/state/consensus/s1.verdict.json"
[[ -f "$VERDICT_FILE" ]] && pass "quorum=1 verdict file written after 1 review" \
  || fail "quorum=1 verdict file written after 1 review"
if [[ -f "$VERDICT_FILE" ]]; then
  STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  assert_eq "quorum=1 single APPROVED review → APPROVED" "APPROVED" "$STATUS"
fi
rm -rf "$DIR"

# Multi-reviewer flow — quorum = 3, 2 APPROVED + 1 REJECTED with 2
# critical issues → REJECTED regardless of agreement.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
tmp_cfg="$DIR/vibeflow.config.json.tmp"
jq '. + {consensus: {quorum: 3}}' "$DIR/vibeflow.config.json" > "$tmp_cfg" \
  && mv "$tmp_cfg" "$DIR/vibeflow.config.json"
for verdict_input in \
  '{"session_id":"s2","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}' \
  '{"session_id":"s2","subagent_type":"chatgpt-reviewer","tool_response":{"content":[{"text":"Final: APPROVED\ncritical issues: 0"}]}}' \
  '{"session_id":"s2","subagent_type":"gemini-reviewer","tool_response":{"content":[{"text":"Verdict: REJECTED\ncritical issues: 2"}]}}'
do
  printf '%s' "$verdict_input" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
done
VERDICT_FILE="$DIR/.vibeflow/state/consensus/s2.verdict.json"
[[ -f "$VERDICT_FILE" ]] && pass "quorum=3 verdict file written after 3 reviews" \
  || fail "quorum=3 verdict file written after 3 reviews"
if [[ -f "$VERDICT_FILE" ]]; then
  STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  assert_eq "2 critical issues → REJECTED" "REJECTED" "$STATUS"
fi
rm -rf "$DIR"

# Timeout: team mode expects 3 reviewers, only 1 shows up, but the
# session log's oldest entry is > 600s old. The aggregator must
# force-finalize with timeout=true and demote APPROVED → NEEDS_REVISION
# (partial quorum cannot ship an APPROVED verdict). We pre-seed the
# session log with an old APPROVED entry, then fire a fresh APPROVED
# through the hook to trigger evaluation.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
tmp_cfg="$DIR/vibeflow.config.json.tmp"
jq '. + {consensus: {quorum: 3}}' "$DIR/vibeflow.config.json" > "$tmp_cfg" \
  && mv "$tmp_cfg" "$DIR/vibeflow.config.json"
CONS_DIR="$DIR/.vibeflow/state/consensus"
mkdir -p "$CONS_DIR"
OLD_TS="2020-01-01T00:00:00Z"
printf '{"recordedAt":"%s","reviewer":"claude-reviewer","verdict":"APPROVED","criticalIssues":0}\n' \
  "$OLD_TS" > "$CONS_DIR/s3.jsonl"
INPUT='{"session_id":"s3","subagent_type":"chatgpt-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
printf '%s' "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
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

# -----------------------------------------------------------------------------
# Sprint 13-A: phase-write-guard.sh (PreToolUse/Write|Edit).
# Blocks cross-phase writes; allow-list per phase in phase-policy.json.
# -----------------------------------------------------------------------------
echo
echo "== phase-write-guard.sh [S13-A] =="

# 1. REQUIREMENTS + src/foo.ts → block (exit 2), stderr names phase + path.
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
OUT_ERR="$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" 2>&1 >/dev/null || true)"
RC=$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null; echo $?)
assert_eq "[S13-A] REQUIREMENTS blocks src/foo.ts (exit 2)" "2" "$RC"
assert_contains "[S13-A] block message names REQUIREMENTS phase" "REQUIREMENTS" "$OUT_ERR"
assert_contains "[S13-A] block message names the offending path" "src/foo.ts" "$OUT_ERR"
rm -rf "$DIR"

# 2. REQUIREMENTS + docs/prd.md → allow (exit 0).
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/docs/prd.md"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] REQUIREMENTS allows docs/prd.md" "0" "$RC"
rm -rf "$DIR"

# 3. REQUIREMENTS + .vibeflow/reports/x.md → allow (framework state is always writable).
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/.vibeflow/reports/x.md"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] REQUIREMENTS allows .vibeflow/reports/x.md" "0" "$RC"
rm -rf "$DIR"

# 4. REQUIREMENTS + vibeflow.config.json → allow (framework config is always writable).
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/vibeflow.config.json"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] REQUIREMENTS allows vibeflow.config.json" "0" "$RC"
rm -rf "$DIR"

# 5. DESIGN + src/foo.ts → block.
DIR="$(make_project DESIGN)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] DESIGN blocks src/foo.ts" "2" "$RC"
rm -rf "$DIR"

# 6. DESIGN + design/tokens.json → allow.
DIR="$(make_project DESIGN)"
mkdir -p "$DIR/design"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/design/tokens.json"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] DESIGN allows design/tokens.json" "0" "$RC"
rm -rf "$DIR"

# 7. DEVELOPMENT + src/foo.ts → allow (full write).
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] DEVELOPMENT allows src/foo.ts" "0" "$RC"
rm -rf "$DIR"

# 8. TESTING + src/foo.ts (non-test) → allow but warn on stderr.
DIR="$(make_project TESTING)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
OUT_ERR="$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" 2>&1 >/dev/null || true)"
RC=$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null; echo $?)
assert_eq "[S13-A] TESTING allows src/foo.ts (warn only)" "0" "$RC"
assert_contains "[S13-A] TESTING src/ warning surfaced on stderr" "warn-only" "$OUT_ERR"
rm -rf "$DIR"

# 9. TESTING + src/foo.test.ts → allow silently (test files are the sanctioned writes).
DIR="$(make_project TESTING)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.test.ts"}}'
OUT_ERR="$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" 2>&1 >/dev/null || true)"
RC=$(echo "$INPUT" | bash "$SCRIPTS/phase-write-guard.sh" >/dev/null 2>/dev/null; echo $?)
assert_eq "[S13-A] TESTING allows src/foo.test.ts silently" "0" "$RC"
if [[ -z "$OUT_ERR" ]]; then
  pass "[S13-A] TESTING src/foo.test.ts emits no stderr"
else
  fail "[S13-A] TESTING src/foo.test.ts emits no stderr (got: $OUT_ERR)"
fi
rm -rf "$DIR"

# 10. Escape hatch: VF_ALLOW_PHASE_WRITE=1 unblocks even REQUIREMENTS.
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
VF_ALLOW_PHASE_WRITE=1 bash "$SCRIPTS/phase-write-guard.sh" <<<"$INPUT" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] escape hatch VF_ALLOW_PHASE_WRITE=1 always allows" "0" "$RC"
rm -rf "$DIR"

# 11. Missing policy file → fail-safe allow (never brick an install).
DIR="$(make_project REQUIREMENTS)"
export VIBEFLOW_CWD="$DIR"
# Point to a non-existent policy via env-shadowing isn't supported; instead
# rename the real policy briefly in a sandbox copy of the hook.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-sb-XXXXXX")"
cp "$SCRIPTS/_lib.sh" "$SANDBOX/_lib.sh"
sed 's|hooks/scripts/phase-policy.json|hooks/scripts/DOES-NOT-EXIST.json|' \
  "$SCRIPTS/phase-write-guard.sh" > "$SANDBOX/phase-write-guard.sh"
chmod +x "$SANDBOX/phase-write-guard.sh"
INPUT='{"tool_input":{"file_path":"'"$DIR"'/src/foo.ts"}}'
# Use the sandbox hook — it sources its own lib, its policy path will
# resolve to the missing file because we're running from SANDBOX.
echo "$INPUT" | bash "$SANDBOX/phase-write-guard.sh" >/dev/null 2>/dev/null
RC=$?
assert_eq "[S13-A] missing policy → fail-safe allow" "0" "$RC"
rm -rf "$SANDBOX" "$DIR"

unset VIBEFLOW_CWD

# -----------------------------------------------------------------------------
# Sprint 11-C: filesystem backend compatibility.
# Verifies that vf_current_phase / vf_last_consensus_status / vf_satisfied_criteria
# prefer project.json over state.db, and fall back gracefully when only one of
# the two is present.
# -----------------------------------------------------------------------------
echo
echo "== _lib.sh filesystem backend [S11-C] =="

make_fs_project() {
  local phase="$1"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-fs-XXXXXX")"
  cat > "$dir/vibeflow.config.json" <<EOF
{
  "project": "testproj",
  "domain": "general",
  "currentPhase": "$phase"
}
EOF
  mkdir -p "$dir/.vibeflow/state/testproj/events"
  cat > "$dir/.vibeflow/state/testproj/project.json" <<EOF
{
  "projectId": "testproj",
  "currentPhase": "$phase",
  "satisfiedCriteria": ["fs.criterion.one"],
  "lastConsensus": {
    "phase": "REQUIREMENTS",
    "status": "NEEDS_REVISION",
    "agreement": 0.72,
    "criticalIssues": 1,
    "recordedAt": "2026-04-20T00:00:00Z"
  },
  "updatedAt": "2026-04-20T00:00:00Z",
  "revision": 2,
  "schemaVersion": 1
}
EOF
  echo "$dir"
}

# 1. project.json alone → helpers read filesystem backend.
DIR="$(make_fs_project ARCHITECTURE)"
export VIBEFLOW_CWD="$DIR"
PHASE="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_current_phase")"
assert_eq "[S11-C] project.json drives vf_current_phase" "ARCHITECTURE" "$PHASE"

STATUS="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_last_consensus_status" || true)"
assert_eq "[S11-C] project.json drives vf_last_consensus_status" "NEEDS_REVISION" "$STATUS"

CRITERIA="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_satisfied_criteria")"
assert_contains "[S11-C] project.json drives vf_satisfied_criteria" "fs.criterion.one" "$CRITERIA"
rm -rf "$DIR"

# 2. Both backends present → filesystem wins (project.json takes precedence over state.db).
DIR="$(make_fs_project TESTING)"
export VIBEFLOW_CWD="$DIR"
sqlite3 "$DIR/.vibeflow/state.db" <<SQL
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
  'DEPLOYMENT',
  '["sqlite.criterion"]',
  '{"phase":"TESTING","status":"APPROVED","agreement":0.95,"criticalIssues":0,"recordedAt":"2026-04-01T00:00:00Z"}',
  '2026-04-01T00:00:00Z',
  2
);
SQL
PHASE="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_current_phase")"
assert_eq "[S11-C] filesystem wins over sqlite for vf_current_phase" "TESTING" "$PHASE"

STATUS="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_last_consensus_status" || true)"
assert_eq "[S11-C] filesystem wins over sqlite for vf_last_consensus_status" "NEEDS_REVISION" "$STATUS"

CRITERIA="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_satisfied_criteria")"
assert_contains "[S11-C] filesystem wins over sqlite for vf_satisfied_criteria" "fs.criterion.one" "$CRITERIA"
rm -rf "$DIR"

# 3. No project.json, sqlite only → helpers still return legacy data (backwards compat).
DIR="$(make_project DESIGN)"
export VIBEFLOW_CWD="$DIR"
PHASE="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_current_phase")"
assert_eq "[S11-C] sqlite-only path still works for vf_current_phase" "DESIGN" "$PHASE"
rm -rf "$DIR"

# 4. No project.json, no sqlite → fallback to config.currentPhase.
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-hooks-empty-XXXXXX")"
cat > "$DIR/vibeflow.config.json" <<EOF
{ "project": "testproj", "currentPhase": "PLANNING" }
EOF
export VIBEFLOW_CWD="$DIR"
PHASE="$(bash -c "source '$SCRIPTS/_lib.sh'; vf_current_phase")"
assert_eq "[S11-C] empty state → config.currentPhase fallback" "PLANNING" "$PHASE"
rm -rf "$DIR"

unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== load-sdlc-context.sh override advisory [S17-C] =="

# When a phase_advanced event exists with humanOverrideNote in its
# payload, load-sdlc-context surfaces it on SessionStart as a visible
# advisory line.
DIR="$(make_project DESIGN)"
export VIBEFLOW_CWD="$DIR"
PROJECT_ID="$(jq -r '.project' "$DIR/vibeflow.config.json")"
EVENTS_DIR="$DIR/.vibeflow/state/$PROJECT_ID/events"
mkdir -p "$EVENTS_DIR"
cat > "$EVENTS_DIR/0003-phase_advanced.json" <<EOF
{
  "seq": 3,
  "revision": 3,
  "projectId": "$PROJECT_ID",
  "recordedAt": "2026-04-21T10:00:00Z",
  "actor": "sdlc_advance_phase",
  "prevRevision": 2,
  "schemaVersion": 1,
  "type": "phase_advanced",
  "payload": {
    "from": "REQUIREMENTS",
    "to": "DESIGN",
    "force": false,
    "humanOverrideNote": "YOS tier resolved offline with Legal"
  }
}
EOF

OV_OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
assert_contains "[S17-C] override event surfaced on SessionStart" "HUMAN_APPROVAL_REQUIRED" "$OV_OUT"
assert_contains "[S17-C] override note text printed" "YOS tier resolved" "$OV_OUT"

# Without the humanOverrideNote field, advisory is silent.
cat > "$EVENTS_DIR/0003-phase_advanced.json" <<EOF
{"seq":3,"revision":3,"projectId":"$PROJECT_ID","recordedAt":"2026-04-21T10:00:00Z","actor":"sdlc_advance_phase","prevRevision":2,"schemaVersion":1,"type":"phase_advanced","payload":{"from":"REQUIREMENTS","to":"DESIGN","force":false}}
EOF
NO_OV_OUT="$(bash "$SCRIPTS/load-sdlc-context.sh")"
if [[ "$NO_OV_OUT" == *"HUMAN_APPROVAL_REQUIRED"* ]]; then
  fail "[S17-C] no override → no advisory emitted"
else
  pass "[S17-C] no override → no advisory emitted"
fi

rm -rf "$DIR"
unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== consensus-aggregator.sh round-aware [S17-A] =="

# Orchestrator writes current-round.txt before each round; aggregator
# reads it, filters jsonl by round, and accumulates rounds[] in
# verdict.json.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
tmp_cfg="$DIR/vibeflow.config.json.tmp"
jq '. + {consensus: {quorum: 1}}' "$DIR/vibeflow.config.json" > "$tmp_cfg" \
  && mv "$tmp_cfg" "$DIR/vibeflow.config.json"
CONS_DIR="$DIR/.vibeflow/state/consensus"
mkdir -p "$CONS_DIR"

# Round 1 — NEEDS_REVISION (single reviewer, criticalIssues=0 so not
# REJECTED, but agreement 1.0 so not NEEDS_REVISION… actually single
# APPROVED gives APPROVED). We want a non-APPROVED round 1. Use a
# claude-reviewer line that says NEEDS_REVISION.
echo "1" > "$CONS_DIR/r17.current-round.txt"
INPUT='{"session_id":"r17","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: NEEDS_REVISION\ncritical issues: 1"}]}}'
printf '%s' "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
VERDICT_FILE="$CONS_DIR/r17.verdict.json"
[[ -f "$VERDICT_FILE" ]] && pass "[S17-A] round 1 verdict file written" \
  || fail "[S17-A] round 1 verdict file written"
if [[ -f "$VERDICT_FILE" ]]; then
  R1_LEN="$(jq -r '.rounds | length' "$VERDICT_FILE")"
  assert_eq "[S17-A] verdict.rounds has 1 entry after round 1" "1" "$R1_LEN"
  R1_NUM="$(jq -r '.rounds[0].round' "$VERDICT_FILE")"
  assert_eq "[S17-A] round 1 entry has round=1" "1" "$R1_NUM"
  R1_STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  # Sprint 17-B rule change: NEEDS_REVISION is only demoted to
  # REJECTED on rejected-majority OR criticalTotal>=2. 1 reviewer
  # saying NEEDS_REVISION + 1 critical = NEEDS_REVISION, not REJECTED.
  assert_eq "[S17-A] round 1 top-level status preserved as NEEDS_REVISION" "NEEDS_REVISION" "$R1_STATUS"
fi

# Round 2 — orchestrator advances round marker, runs new reviewer.
# Verdict this time: APPROVED with 0 critical. Single-reviewer quorum,
# so aggregator finalises and appends to rounds[].
echo "2" > "$CONS_DIR/r17.current-round.txt"
INPUT='{"session_id":"r17","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
printf '%s' "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
if [[ -f "$VERDICT_FILE" ]]; then
  R2_LEN="$(jq -r '.rounds | length' "$VERDICT_FILE")"
  assert_eq "[S17-A] verdict.rounds has 2 entries after round 2" "2" "$R2_LEN"
  R2_NUM="$(jq -r '.rounds[1].round' "$VERDICT_FILE")"
  assert_eq "[S17-A] round 2 entry has round=2" "2" "$R2_NUM"
  R2_STATUS="$(jq -r '.status' "$VERDICT_FILE")"
  assert_eq "[S17-A] round 2 top-level status APPROVED (latest)" "APPROVED" "$R2_STATUS"
  FINAL_ROUND="$(jq -r '.finalRound' "$VERDICT_FILE")"
  assert_eq "[S17-A] verdict.finalRound == 2" "2" "$FINAL_ROUND"
fi

# Archival — each round's jsonl is archived under a round-numbered name
# when current-round.txt is present.
R1_ARCHIVE="$CONS_DIR/r17.r1.archived.jsonl"
R2_ARCHIVE="$CONS_DIR/r17.r2.archived.jsonl"
[[ -f "$R1_ARCHIVE" ]] && pass "[S17-A] round 1 jsonl archived as r1.archived.jsonl" \
  || fail "[S17-A] round 1 jsonl archived as r1.archived.jsonl"
[[ -f "$R2_ARCHIVE" ]] && pass "[S17-A] round 2 jsonl archived as r2.archived.jsonl" \
  || fail "[S17-A] round 2 jsonl archived as r2.archived.jsonl"

# Round-marker sanity: if marker is absent, CURRENT_ROUND defaults to 1.
DIR2="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR2"
jq '. + {consensus: {quorum: 1}}' "$DIR2/vibeflow.config.json" > "$DIR2/cfg.tmp" \
  && mv "$DIR2/cfg.tmp" "$DIR2/vibeflow.config.json"
INPUT='{"session_id":"legacy","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
printf '%s' "$INPUT" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
LV="$DIR2/.vibeflow/state/consensus/legacy.verdict.json"
if [[ -f "$LV" ]]; then
  LEGACY_ROUND="$(jq -r '.finalRound' "$LV")"
  assert_eq "[S17-A] no marker → finalRound defaults to 1" "1" "$LEGACY_ROUND"
  # Legacy archival: single-round session uses epoch-suffix archive
  LEGACY_ARCHIVES="$(ls "$DIR2/.vibeflow/state/consensus/" | grep 'legacy\.[0-9]*\.archived\.jsonl' | head -1)"
  if [[ -n "$LEGACY_ARCHIVES" ]]; then
    pass "[S17-A] legacy single-round keeps epoch-suffix archive name"
  else
    fail "[S17-A] legacy single-round keeps epoch-suffix archive name"
  fi
fi

rm -rf "$DIR" "$DIR2"
unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== consensus-aggregator.sh critical dedup [S17-B] =="

# Three reviewers flag the SAME underlying finding (same file +
# line_range). Naive sum = 3; dedup → 1; aggregator must use 1 so
# the REJECTED threshold (≥2) is not falsely tripped.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
jq '. + {consensus: {quorum: 3}}' "$DIR/vibeflow.config.json" > "$DIR/cfg.tmp" \
  && mv "$DIR/cfg.tmp" "$DIR/vibeflow.config.json"

SAME_FINDING='{"id":"ID","target":{"file":"docs/prd.md","line_range":[120,145]},"title":"Data residency for BDDK BISY missing","rationale":"7-year audit logs..."}'

for rev in claude-reviewer codex-reviewer gemini-reviewer; do
  ID="${rev:0:1}1"
  ITEM="$(printf '%s' "$SAME_FINDING" | sed "s/\"ID\"/\"$ID\"/")"
  PAYLOAD="$(jq -n --arg rev "$rev" --arg item "$ITEM" '{
    session_id:"dedup1",
    subagent_type:$rev,
    tool_response:{content:[{text: ("{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[" + $item + "]}")}]}
  }')"
  printf '%s' "$PAYLOAD" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
done

DEDUP_VERDICT="$DIR/.vibeflow/state/consensus/dedup1.verdict.json"
[[ -f "$DEDUP_VERDICT" ]] && pass "[S17-B] verdict written after 3 same-finding reviews" \
  || fail "[S17-B] verdict written after 3 same-finding reviews"
if [[ -f "$DEDUP_VERDICT" ]]; then
  CRITICAL_TOTAL="$(jq -r '.criticalTotal' "$DEDUP_VERDICT")"
  assert_eq "[S17-B] same finding deduped across 3 reviewers → criticalTotal==1" "1" "$CRITICAL_TOTAL"
  CRITICAL_RAW="$(jq -r '.criticalRawCount' "$DEDUP_VERDICT")"
  assert_eq "[S17-B] criticalRawCount preserved for audit (==3)" "3" "$CRITICAL_RAW"
  DEDUPED_LEN="$(jq -r '.criticalDeduped | length' "$DEDUP_VERDICT")"
  assert_eq "[S17-B] criticalDeduped array length == 1" "1" "$DEDUPED_LEN"
  STATUS="$(jq -r '.status' "$DEDUP_VERDICT")"
  # 3 NEEDS_REVISION, 0 critical after dedup → status = NEEDS_REVISION.
  assert_eq "[S17-B] status NEEDS_REVISION (not falsely REJECTED)" "NEEDS_REVISION" "$STATUS"
fi
rm -rf "$DIR"

# Dedup by Jaccard title similarity, not just exact target match.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
jq '. + {consensus: {quorum: 2}}' "$DIR/vibeflow.config.json" > "$DIR/cfg.tmp" \
  && mv "$DIR/cfg.tmp" "$DIR/vibeflow.config.json"
# Different line_range, same underlying title words (>0.6 Jaccard)
ITEM_A='{"id":"A1","target":{"file":"docs/prd.md","line_range":[10,20]},"title":"latency SLA ambiguity hard goal or soft","rationale":"..."}'
ITEM_B='{"id":"B1","target":{"file":"docs/prd.md","line_range":[15,25]},"title":"latency SLA ambiguity hard goal versus soft","rationale":"..."}'

PAYLOAD_A="$(jq -n --arg rev "claude-reviewer" --arg item "$ITEM_A" '{
  session_id:"jac1", subagent_type:$rev,
  tool_response:{content:[{text:("{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[" + $item + "]}")}]}
}')"
PAYLOAD_B="$(jq -n --arg rev "codex-reviewer" --arg item "$ITEM_B" '{
  session_id:"jac1", subagent_type:$rev,
  tool_response:{content:[{text:("{\"verdict\":\"NEEDS_REVISION\",\"criticalIssues\":[" + $item + "]}")}]}
}')"
printf '%s' "$PAYLOAD_A" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
printf '%s' "$PAYLOAD_B" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
JAC_VERDICT="$DIR/.vibeflow/state/consensus/jac1.verdict.json"
if [[ -f "$JAC_VERDICT" ]]; then
  JAC_CRITICAL="$(jq -r '.criticalTotal' "$JAC_VERDICT")"
  assert_eq "[S17-B] Jaccard-similar titles deduped → criticalTotal==1" "1" "$JAC_CRITICAL"
  JAC_RAW="$(jq -r '.criticalRawCount' "$JAC_VERDICT")"
  assert_eq "[S17-B] Jaccard case criticalRawCount==2" "2" "$JAC_RAW"
fi
rm -rf "$DIR"

# Legacy integer-count reviewers still sum (no dedup possible).
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
jq '. + {consensus: {quorum: 2}}' "$DIR/vibeflow.config.json" > "$DIR/cfg.tmp" \
  && mv "$DIR/cfg.tmp" "$DIR/vibeflow.config.json"
for rev in claude-reviewer codex-reviewer; do
  PAYLOAD="$(jq -n --arg rev "$rev" '{
    session_id:"leg1", subagent_type:$rev,
    tool_response:{content:[{text:"Verdict: NEEDS_REVISION\ncritical issues: 1"}]}
  }')"
  printf '%s' "$PAYLOAD" | bash "$SCRIPTS/consensus-aggregator.sh" >/dev/null
done
LEG_VERDICT="$DIR/.vibeflow/state/consensus/leg1.verdict.json"
if [[ -f "$LEG_VERDICT" ]]; then
  LEG_CRITICAL="$(jq -r '.criticalTotal' "$LEG_VERDICT")"
  assert_eq "[S17-B] legacy integer counts fall back to sum (1+1==2)" "2" "$LEG_CRITICAL"
  LEG_RAW="$(jq -r '.criticalRawCount' "$LEG_VERDICT")"
  assert_eq "[S17-B] legacy path criticalRawCount==0 (no structured items)" "0" "$LEG_RAW"
fi
rm -rf "$DIR"
unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== consensus-gate.sh [S16-A] =="

GATE="$SCRIPTS/consensus-gate.sh"

# Fixture: project with an active consensus-needed.json marker.
DIR="$(make_project DEVELOPMENT)"
export VIBEFLOW_CWD="$DIR"
mkdir -p "$DIR/.vibeflow/state"
cat > "$DIR/.vibeflow/state/consensus-needed.json" <<EOF
{
  "artifact": ".vibeflow/reports/prd-quality-report.md",
  "requiredCommand": "/vibeflow:consensus-orchestrator .vibeflow/reports/prd-quality-report.md",
  "createdAt": "2026-04-20T00:00:00Z"
}
EOF

# 1. Bash tool call unrelated to consensus is BLOCKED when marker is present.
INPUT='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] marker blocks unrelated Bash (exit 2)" "2" "$RC"
assert_contains "[S16-A] block message names required command" "/vibeflow:consensus-orchestrator" "$OUT"
assert_contains "[S16-A] block message names the artifact" "prd-quality-report.md" "$OUT"

# 2. Bash command that IS the consensus chain is allowed through.
INPUT='{"tool_name":"Bash","tool_input":{"command":"/vibeflow:consensus-orchestrator foo.md"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] consensus-orchestrator command passes through (exit 0)" "0" "$RC"

INPUT='{"tool_name":"Bash","tool_input":{"command":"/vibeflow:apply-arbiter-patch latest"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] apply-arbiter-patch command passes through (exit 0)" "0" "$RC"

# 3. Bash command that removes the marker is allowed.
INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -f .vibeflow/state/consensus-needed.json"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] rm marker passes through (exit 0)" "0" "$RC"

# 4. Write under .vibeflow/** is allowed (framework state writes stay open).
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$DIR"'/.vibeflow/reports/foo.md","content":"x"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] Write under .vibeflow/** passes through (exit 0)" "0" "$RC"

# 5. Write to a source file is BLOCKED while marker is present.
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$DIR"'/src/foo.ts","content":"x"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] Write to src/** blocked (exit 2)" "2" "$RC"

# 6. Env override bypasses the gate.
INPUT='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
OUT="$(printf '%s' "$INPUT" | VF_SKIP_CONSENSUS_GATE=1 bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] VF_SKIP_CONSENSUS_GATE=1 bypasses (exit 0)" "0" "$RC"

# 7. No marker → fail-safe allow.
rm -f "$DIR/.vibeflow/state/consensus-needed.json"
INPUT='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
OUT="$(printf '%s' "$INPUT" | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] no marker → allow (exit 0)" "0" "$RC"

# 8. Empty stdin → fail-safe allow.
OUT="$(printf '' | bash "$GATE" 2>&1)"
RC=$?
assert_eq "[S16-A] empty stdin → allow (exit 0)" "0" "$RC"

rm -rf "$DIR"
unset VIBEFLOW_CWD

# ---------------------------------------------------------------------------
echo "== save-plan-doc.sh [S19-PLAN] =="

SPD="$SCRIPTS/save-plan-doc.sh"
[[ -x "$SPD" ]] && pass "[S19-PLAN] save-plan-doc.sh is executable" \
  || fail "[S19-PLAN] save-plan-doc.sh is executable"

# Sprint-numbered title → docs/SPRINT-N.md
DIR="$(make_project REQUIREMENTS)"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/vf-planhome-XXXXXX")"
mkdir -p "$FAKE_HOME/.claude/plans"
cat > "$FAKE_HOME/.claude/plans/sprint99-test.md" <<'PLAN_EOF'
# Sprint 99 — Hook smoke test

## Context
Testing save-plan-doc hook fixture.
PLAN_EOF
INPUT="$(jq -n --arg cwd "$DIR" '{cwd:$cwd, tool_name:"ExitPlanMode", tool_input:{}, tool_response:{}}')"
HOME_ORIG="$HOME"
export HOME="$FAKE_HOME"
printf '%s' "$INPUT" | bash "$SPD" 2>/dev/null
export HOME="$HOME_ORIG"
if [[ -f "$DIR/docs/SPRINT-99.md" ]]; then
  pass "[S19-PLAN] sprint-numbered title writes docs/SPRINT-99.md"
else
  fail "[S19-PLAN] sprint-numbered title writes docs/SPRINT-99.md"
fi
if [[ -f "$DIR/docs/SPRINT-99.md" ]] && grep -q "# Sprint 99" "$DIR/docs/SPRINT-99.md"; then
  pass "[S19-PLAN] written SPRINT-99.md preserves plan content"
else
  fail "[S19-PLAN] written SPRINT-99.md preserves plan content"
fi
rm -rf "$DIR" "$FAKE_HOME"

# Non-sprint title → docs/plans/<slug>-<date>.md fallback
DIR="$(make_project REQUIREMENTS)"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/vf-planhome-XXXXXX")"
mkdir -p "$FAKE_HOME/.claude/plans"
cat > "$FAKE_HOME/.claude/plans/refactor-plan.md" <<'PLAN_EOF'
# Refactor — lift consensus rule into shared lib

## Context
Not a sprint, just a refactor.
PLAN_EOF
INPUT="$(jq -n --arg cwd "$DIR" '{cwd:$cwd, tool_name:"ExitPlanMode", tool_input:{}, tool_response:{}}')"
HOME_ORIG="$HOME"
export HOME="$FAKE_HOME"
printf '%s' "$INPUT" | bash "$SPD" 2>/dev/null
export HOME="$HOME_ORIG"
FALLBACK_COUNT="$(find "$DIR/docs/plans" -maxdepth 1 -name 'refactor*' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$FALLBACK_COUNT" -ge 1 ]]; then
  pass "[S19-PLAN] non-sprint title falls back to docs/plans/<slug>-*.md"
else
  fail "[S19-PLAN] non-sprint title falls back to docs/plans/<slug>-*.md"
fi
rm -rf "$DIR" "$FAKE_HOME"

# Guard: no vibeflow.config.json → no write
DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-nonproj-XXXXXX")"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/vf-planhome-XXXXXX")"
mkdir -p "$FAKE_HOME/.claude/plans"
cat > "$FAKE_HOME/.claude/plans/sprint77-should-not-save.md" <<'PLAN_EOF'
# Sprint 77 — Should NOT save

(No vibeflow.config.json in target cwd.)
PLAN_EOF
INPUT="$(jq -n --arg cwd "$DIR" '{cwd:$cwd, tool_name:"ExitPlanMode", tool_input:{}, tool_response:{}}')"
HOME_ORIG="$HOME"
export HOME="$FAKE_HOME"
printf '%s' "$INPUT" | bash "$SPD" 2>/dev/null
export HOME="$HOME_ORIG"
if [[ ! -f "$DIR/docs/SPRINT-77.md" ]]; then
  pass "[S19-PLAN] non-VibeFlow project → no write (guard)"
else
  fail "[S19-PLAN] non-VibeFlow project → no write (guard)"
fi
rm -rf "$DIR" "$FAKE_HOME"

# Env bypass VF_SKIP_PLAN_SAVE=1
DIR="$(make_project REQUIREMENTS)"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/vf-planhome-XXXXXX")"
mkdir -p "$FAKE_HOME/.claude/plans"
cat > "$FAKE_HOME/.claude/plans/sprint55-bypass.md" <<'PLAN_EOF'
# Sprint 55 — Bypass test
PLAN_EOF
INPUT="$(jq -n --arg cwd "$DIR" '{cwd:$cwd, tool_name:"ExitPlanMode", tool_input:{}, tool_response:{}}')"
HOME_ORIG="$HOME"
export HOME="$FAKE_HOME"
printf '%s' "$INPUT" | VF_SKIP_PLAN_SAVE=1 bash "$SPD" 2>/dev/null
export HOME="$HOME_ORIG"
if [[ ! -f "$DIR/docs/SPRINT-55.md" ]]; then
  pass "[S19-PLAN] VF_SKIP_PLAN_SAVE=1 → no write"
else
  fail "[S19-PLAN] VF_SKIP_PLAN_SAVE=1 → no write"
fi
rm -rf "$DIR" "$FAKE_HOME"

# hooks.json wiring
HJSON="$REPO_ROOT/hooks/hooks.json"
if jq -e '.hooks.PostToolUse[] | select(.matcher == "ExitPlanMode") | .hooks[] | select(.command | test("save-plan-doc"))' "$HJSON" >/dev/null 2>&1; then
  pass "[S19-PLAN] hooks.json PostToolUse registers save-plan-doc on ExitPlanMode"
else
  fail "[S19-PLAN] hooks.json PostToolUse registers save-plan-doc on ExitPlanMode"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
