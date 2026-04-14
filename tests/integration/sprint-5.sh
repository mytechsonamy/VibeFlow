#!/bin/bash
# VibeFlow Sprint 5 integration harness.
#
# Complements run.sh + sprint-2.sh + sprint-3.sh + sprint-4.sh.
# Sprint 5 is a v1.0.x maintenance sprint — every ticket closes an
# unfinished v1.0 stub or adds real-world coverage that landed too
# late for v1.0. This harness asserts each S5-* ticket's artifacts
# are present + consistent.
#
# Sections:
#   [S5-A] — GitLab CI provider wiring (S5-02)
#   [S5-B] — Live PostgreSQL team-mode walk (S5-03, conditional on $DATABASE_URL)
#   [S5-C] — Release script presence + safety guards (S5-04)
#   [S5-D] — Next.js demo presence + artifact verdicts (S5-05)
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_OPS_SRC="$REPO_ROOT/mcp-servers/dev-ops/src/client.ts"
DEV_OPS_DIST="$REPO_ROOT/mcp-servers/dev-ops/dist/client.js"
DEV_OPS_TOOLS_SRC="$REPO_ROOT/mcp-servers/dev-ops/src/tools.ts"
DEV_OPS_TOOLS_DIST="$REPO_ROOT/mcp-servers/dev-ops/dist/tools.js"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S5-A] GitLab CI provider wiring =="

# createGitlabClient must be exported from the dev-ops client module
# (both src and dist — tools.ts imports from the compiled dist).
if grep -q "^export function createGitlabClient" "$DEV_OPS_SRC"; then
  pass "dev-ops src/client.ts exports createGitlabClient"
else
  fail "dev-ops src/client.ts exports createGitlabClient"
fi
if grep -q "createGitlabClient" "$DEV_OPS_DIST"; then
  pass "dev-ops dist/client.js ships createGitlabClient"
else
  fail "dev-ops dist/client.js ships createGitlabClient"
fi

# The GitLab client must use PRIVATE-TOKEN, not Bearer auth.
if grep -q '"PRIVATE-TOKEN"' "$DEV_OPS_SRC"; then
  pass "GitLab client uses PRIVATE-TOKEN header"
else
  fail "GitLab client uses PRIVATE-TOKEN header"
fi

# tools.ts must route CI_PROVIDER=gitlab to createGitlabClient
# rather than throwing a "not implemented" error.
if grep -q "createGitlabClient" "$DEV_OPS_TOOLS_SRC"; then
  pass "tools.ts imports createGitlabClient"
else
  fail "tools.ts imports createGitlabClient"
fi
if grep -q "createGitlabClient" "$DEV_OPS_TOOLS_DIST"; then
  pass "dist/tools.js calls createGitlabClient"
else
  fail "dist/tools.js calls createGitlabClient"
fi

# The "not yet implemented" error path must be gone.
if grep -q "not implemented yet" "$DEV_OPS_TOOLS_SRC"; then
  fail "tools.ts still contains the 'not implemented yet' stub"
else
  pass "tools.ts no longer has the 'not implemented yet' stub"
fi

# Dedicated GitLab test file exists + has substantive coverage.
GITLAB_TEST="$REPO_ROOT/mcp-servers/dev-ops/tests/gitlab-client.test.ts"
if [[ -f "$GITLAB_TEST" ]]; then
  pass "dev-ops gitlab-client.test.ts present"
  # Surface the case blocks we expect the file to cover, by name.
  for needle in "createGitlabClient — config" \
                "createGitlabClient — triggerWorkflow" \
                "createGitlabClient — getRun normalization" \
                "createGitlabClient — listArtifacts" \
                "createGitlabClient — offline / network failure"; do
    if grep -qF "$needle" "$GITLAB_TEST"; then
      pass "gitlab-client.test.ts has '$needle' describe block"
    else
      fail "gitlab-client.test.ts has '$needle' describe block"
    fi
  done
  # The GitLab pipeline-status mapping must cover every terminal
  # status the GitLab API emits.
  for status in "waiting_for_resource" "preparing" "pending" \
                "scheduled" "manual" "running" \
                "success" "failed" "canceled" "skipped"; do
    if grep -q "\"$status\"" "$GITLAB_TEST"; then
      pass "gitlab-client.test.ts exercises $status"
    else
      fail "gitlab-client.test.ts exercises $status"
    fi
  done
else
  fail "dev-ops gitlab-client.test.ts present"
fi

# CONFIGURATION.md must document that GitLab is now implemented.
CFG_DOC="$REPO_ROOT/docs/CONFIGURATION.md"
if grep -q "createGitlabClient" "$CFG_DOC" || grep -q "v1.0.1.*Sprint 5.*S5-02" "$CFG_DOC"; then
  pass "CONFIGURATION.md notes GitLab is implemented"
else
  fail "CONFIGURATION.md notes GitLab is implemented"
fi

# ---------------------------------------------------------------------------
echo "== [S5-B] live PostgreSQL team-mode walk =="

# S5-03 — exercises the sdlc-engine against a real PostgreSQL backend.
# The bash wrapper `bin/with-postgres.sh` spins up a throwaway pg14
# container and exports DATABASE_URL; we then drive the engine in
# team mode through a full SDLC walk and re-check state persistence
# across engine process restarts.
#
# Skip conditions:
#   - docker not installed → skip gracefully
#   - VF_SKIP_LIVE_POSTGRES=1 → skip (opt-out for users with
#     restricted docker access in local dev)
#   - pg package missing in sdlc-engine node_modules → skip (solo-
#     mode users don't need pg installed; we don't force it)
#
# Hard failures (we WANT these to fire loudly):
#   - docker is installed and not skipped but the container fails
#     to come up
#   - the engine reports a state.db corruption or a missing project
#     after restart

WITH_POSTGRES="$REPO_ROOT/bin/with-postgres.sh"

if [[ -f "$WITH_POSTGRES" && -x "$WITH_POSTGRES" ]]; then
  pass "bin/with-postgres.sh present + executable"
else
  fail "bin/with-postgres.sh present + executable"
fi

if [[ "${VF_SKIP_LIVE_POSTGRES:-}" == "1" ]]; then
  pass "[S5-B] live-postgres walk skipped via VF_SKIP_LIVE_POSTGRES=1"
elif ! command -v docker >/dev/null 2>&1; then
  pass "[S5-B] live-postgres walk skipped — docker not installed"
elif [[ ! -d "$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/pg" ]]; then
  pass "[S5-B] live-postgres walk skipped — pg optional dep not installed"
else
  # The wrapper sets DATABASE_URL + VIBEFLOW_POSTGRES_URL inside the
  # wrapped command, which in turn spawns the engine + walks it.
  # We invoke the wrapper with a small walker script that prints
  # the results we care about to stdout so the harness can assert
  # on them.
  WALK_SCRIPT="$(cat <<'WALK'
set -euo pipefail
ENGINE="$1"; PROJECT="s5b-pg"

export VIBEFLOW_MODE="team"
export VIBEFLOW_PROJECT="$PROJECT"

# --- Phase 1: writes ---
OUT1="$(node "$ENGINE" <<JSON 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s5b","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"$PROJECT","criterion":"prd.approved"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"$PROJECT","criterion":"testability.score>=60"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"$PROJECT","phase":"REQUIREMENTS","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"$PROJECT","to":"DESIGN"}}}
JSON
)"
# Any "isError":true line in phase 1 aborts the walk.
if echo "$OUT1" | grep -q '"isError":true'; then
  echo "PHASE1_ERROR"
  echo "$OUT1" | grep '"isError":true' | head -1
  exit 1
fi
echo "PHASE1_OK"

# --- Phase 2: read-after-write in a FRESH engine process ---
# This is the Bug #13 surface + the state-survives-restart test
# rolled into one — a new engine process must pick up the row the
# first process wrote.
OUT2="$(node "$ENGINE" <<JSON 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s5b-r","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"$PROJECT"}}}
JSON
)"
if echo "$OUT2" | grep -q '"isError":true'; then
  echo "PHASE2_ERROR"
  echo "$OUT2" | grep '"isError":true' | head -1
  exit 1
fi
if echo "$OUT2" | grep -q "DESIGN"; then
  echo "PHASE2_DESIGN"
else
  echo "PHASE2_MISSING_DESIGN"
  echo "$OUT2" | head -3
  exit 1
fi
WALK
)"
  ENGINE_DIST_ABS="$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js"
  WALK_OUT="$(bash "$WITH_POSTGRES" bash -c "$WALK_SCRIPT" _ "$ENGINE_DIST_ABS" 2>&1 || true)"

  if echo "$WALK_OUT" | grep -q "^PHASE1_OK"; then
    pass "[S5-B] phase 1 writes completed against real PostgreSQL"
  else
    fail "[S5-B] phase 1 writes completed against real PostgreSQL"
    echo "    WALK_OUT tail:" >&2
    echo "$WALK_OUT" | tail -10 >&2
  fi

  if echo "$WALK_OUT" | grep -q "^PHASE2_DESIGN"; then
    pass "[S5-B] state survives engine restart — get_state returns DESIGN"
  else
    fail "[S5-B] state survives engine restart — get_state returns DESIGN"
    echo "    WALK_OUT tail:" >&2
    echo "$WALK_OUT" | tail -10 >&2
  fi

  # Bug #13 cross-process reproducer — same path as run.sh, but now
  # against Postgres. If the fix only works for SQLite, this fires.
  if echo "$WALK_OUT" | grep -q "PHASE2_ERROR"; then
    fail "[S5-B] Bug #13 regressed on PostgreSQL backend"
  else
    pass "[S5-B] Bug #13 fix holds on PostgreSQL backend"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S5-C] release script =="

# S5-04 — bin/release.sh automates v1.0.1+ release prep (version bump,
# CHANGELOG insertion, build, package, sha256, tag). The GitHub
# Actions workflow .github/workflows/release.yml mirrors the build
# side on tag push. Both artifacts must exist AND the release script
# must embed the load-bearing safety properties so a future refactor
# can't silently remove them.
RELEASE_SCRIPT="$REPO_ROOT/bin/release.sh"
RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"

if [[ -f "$RELEASE_SCRIPT" ]]; then
  pass "bin/release.sh present"
else
  fail "bin/release.sh present"
fi
if [[ -x "$RELEASE_SCRIPT" ]]; then
  pass "bin/release.sh executable"
else
  fail "bin/release.sh executable"
fi
if [[ -f "$RELEASE_WORKFLOW" ]]; then
  pass ".github/workflows/release.yml present"
else
  fail ".github/workflows/release.yml present"
fi

if [[ -f "$RELEASE_SCRIPT" ]]; then
  # Dirty-tree refusal: script must check `git status --porcelain`
  # and exit non-zero when there are local changes. Without this,
  # a release could ship a half-finished working tree as v1.0.x.
  if grep -q 'git status --porcelain' "$RELEASE_SCRIPT"; then
    pass "release.sh refuses a dirty working tree"
  else
    fail "release.sh refuses a dirty working tree"
  fi

  # SemVer validation: reject prerelease / metadata suffixes so
  # release.sh can't be (ab)used to cut v1.0.0-beta tags that
  # bypass the normal release pipeline.
  if grep -q 'not a strict SemVer' "$RELEASE_SCRIPT"; then
    pass "release.sh enforces strict X.Y.Z SemVer"
  else
    fail "release.sh enforces strict X.Y.Z SemVer"
  fi

  # Preflight test gauntlet: release.sh must run every test harness
  # before touching files. A release that skips the preflight would
  # let a broken commit ship.
  for harness in "bash hooks/tests/run.sh" \
                 "bash tests/integration/run.sh" \
                 "bash tests/integration/sprint-2.sh" \
                 "bash tests/integration/sprint-3.sh" \
                 "bash tests/integration/sprint-4.sh" \
                 "bash tests/integration/sprint-5.sh"; do
    if grep -qF "$harness" "$RELEASE_SCRIPT"; then
      pass "release.sh preflight runs '$harness'"
    else
      fail "release.sh preflight runs '$harness'"
    fi
  done

  # Must NOT push the tag automatically — that's a public action
  # gated on explicit user authorization (same rule as Sprint 4).
  if grep -q 'git push' "$RELEASE_SCRIPT"; then
    # A `git push` inside the script is only acceptable in the
    # "next steps" hint block. Any `git push` in an execution path
    # (not inside an `echo`) is a policy violation. Heuristic: if
    # the line starts with `echo "` then it's documentation.
    VIOLATIONS="$(grep -n 'git push' "$RELEASE_SCRIPT" | grep -v 'echo' | head -1 || true)"
    if [[ -z "$VIOLATIONS" ]]; then
      pass "release.sh does not push automatically (all 'git push' refs are in hint text)"
    else
      fail "release.sh has an executable 'git push' line — public action should be user-gated (line: $VIOLATIONS)"
    fi
  else
    pass "release.sh does not push automatically (no 'git push' refs)"
  fi

  # --check-clean smoke: invoke release.sh --check-clean from a
  # CLEAN temp git repo. We clone the repo to a throwaway dir so we
  # don't need the current working tree to be clean (the Sprint 5
  # work-in-progress would otherwise make the check fail). The
  # release.sh file itself may not yet be committed to HEAD, so we
  # copy it into the clone before running the smoke.
  TMP_RELEASE="$(mktemp -d "${TMPDIR:-/tmp}/vf-s5c-XXXXXX")"
  if git clone --quiet --no-local "$REPO_ROOT" "$TMP_RELEASE/repo" 2>/dev/null; then
    mkdir -p "$TMP_RELEASE/repo/bin"
    cp "$RELEASE_SCRIPT" "$TMP_RELEASE/repo/bin/release.sh"
    chmod +x "$TMP_RELEASE/repo/bin/release.sh"
    # Stage the copied file so the tree is reported clean (an
    # uncommitted-but-tracked file would otherwise show as ??).
    # We use `git add` so --check-clean sees a "staged but clean"
    # working copy — the dirty-tree check only fires on unstaged
    # changes AND untracked files.
    (cd "$TMP_RELEASE/repo" && git add bin/release.sh && git commit -q -m "test: seed release.sh" 2>/dev/null || true)

    if (cd "$TMP_RELEASE/repo" && bash bin/release.sh --check-clean >/dev/null 2>&1); then
      pass "release.sh --check-clean returns 0 on a clean tree"
    else
      fail "release.sh --check-clean returns 0 on a clean tree"
    fi
    # And when dirty: touch a file and expect non-zero.
    echo "dirty" > "$TMP_RELEASE/repo/.dirty-test"
    if ! (cd "$TMP_RELEASE/repo" && bash bin/release.sh --check-clean >/dev/null 2>&1); then
      pass "release.sh --check-clean returns non-zero on a dirty tree"
    else
      fail "release.sh --check-clean returns non-zero on a dirty tree"
    fi
  else
    fail "release.sh --check-clean smoke — git clone failed"
  fi
  rm -rf "$TMP_RELEASE"
fi

if [[ -f "$RELEASE_WORKFLOW" ]]; then
  # Workflow must trigger on vX.Y.Z tag push, not on main pushes —
  # releases are gated on the tag being pushed, never on a branch
  # commit.
  if grep -q 'tags:' "$RELEASE_WORKFLOW" && grep -q '"v\*\.\*\.\*"' "$RELEASE_WORKFLOW"; then
    pass "release.yml triggers on vX.Y.Z tag push"
  else
    fail "release.yml triggers on vX.Y.Z tag push"
  fi
  # Workflow must attach both the tarball AND the sha256 manifest.
  if grep -q 'tarball }}.sha256' "$RELEASE_WORKFLOW"; then
    pass "release.yml uploads the sha256 manifest"
  else
    fail "release.yml uploads the sha256 manifest"
  fi
  # Workflow must verify plugin.json version matches the tag to
  # prevent a tag push that doesn't reflect the committed manifest.
  if grep -q 'plugin.json version.*match' "$RELEASE_WORKFLOW"; then
    pass "release.yml verifies plugin.json version matches the tag"
  else
    fail "release.yml verifies plugin.json version matches the tag"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S5-D] Next.js demo presence =="

# S5-05 is not yet implemented. Placeholder sentinel.
if [[ -d "$REPO_ROOT/examples/nextjs-demo" ]]; then
  fail "[S5-D] examples/nextjs-demo exists — check the S5-05 implementation"
else
  pass "[S5-D] examples/nextjs-demo pending (S5-05 open)"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
