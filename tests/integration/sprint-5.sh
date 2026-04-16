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
#   [S5-E] — Bug #13 cross-process reproducer mirror (S5-06)
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
  pass "[S5-B] live-postgres walk skipped — docker binary not installed"
elif ! docker info >/dev/null 2>&1; then
  # Probe the daemon, not just the binary. Closes a latent skip gap
  # where macOS contributors had docker installed but Docker Desktop
  # not running — the walk would fire and fail instead of skip.
  pass "[S5-B] live-postgres walk skipped — docker daemon not running"
elif [[ ! -d "$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/pg" ]]; then
  pass "[S5-B] live-postgres walk skipped — pg optional peer dep not installed"
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
                 "bash tests/integration/sprint-5.sh" \
                 "bash tests/integration/sprint-6.sh" \
                 "bash tests/integration/sprint-7.sh"; do
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

  # ----- [S5-C / S6-07] CHANGELOG insertion runtime sentinel ----------------
  # Sprint 5 / S5-07 uncovered a BSD awk portability bug in release.sh's
  # CHANGELOG insertion step that slipped past every static source-grep
  # check in this section because the bug only surfaced at runtime. Sprint
  # 6 / S6-07 extracts the insertion logic into insert_changelog_entry()
  # + exposes it via `release.sh --test-changelog-insert <version>` so we
  # can exercise the actual runtime path against isolated fixtures here.
  #
  # Three assertions:
  #   1. Happy path — valid fixture + insert → new version header lands
  #      at the top of the rewritten fixture
  #   2. Idempotency check on the old entry — the previous version's
  #      heading survives the insertion (we are PREPENDING, not
  #      REPLACING)
  #   3. Negative path — header-less fixture + insert → exit non-zero
  #      AND the file remains unchanged (no partial write)
  TMP_CHLOG="$(mktemp -d "${TMPDIR:-/tmp}/vf-s5c-chlog-XXXXXX")"
  cat > "$TMP_CHLOG/CHANGELOG.md" <<'CHLOG_HAPPY'
# Changelog

All notable changes are documented in this file.

---

## [1.0.0] — 2026-04-13

Initial release.
CHLOG_HAPPY
  if (cd "$TMP_CHLOG" && bash "$RELEASE_SCRIPT" --test-changelog-insert 9.9.9 >/dev/null 2>&1); then
    if head -20 "$TMP_CHLOG/CHANGELOG.md" | grep -qF "## [9.9.9]"; then
      pass "release.sh --test-changelog-insert: happy-path fixture leads with new version"
    else
      fail "release.sh --test-changelog-insert: happy-path fixture leads with new version"
    fi
    if grep -qF "## [1.0.0]" "$TMP_CHLOG/CHANGELOG.md"; then
      pass "release.sh --test-changelog-insert: previous version survives the insertion"
    else
      fail "release.sh --test-changelog-insert: previous version survives the insertion"
    fi
  else
    fail "release.sh --test-changelog-insert: happy-path exits 0 on valid fixture"
  fi
  rm -rf "$TMP_CHLOG"

  # Negative — a CHANGELOG without any '## [' heading must be refused
  # by the post-insertion verification step.
  TMP_CHLOG_BAD="$(mktemp -d "${TMPDIR:-/tmp}/vf-s5c-chlog-bad-XXXXXX")"
  cat > "$TMP_CHLOG_BAD/CHANGELOG.md" <<'CHLOG_BAD'
# Changelog

This file has no version headings at all.
CHLOG_BAD
  BAD_BEFORE="$(wc -c < "$TMP_CHLOG_BAD/CHANGELOG.md" | tr -d ' ')"
  if (cd "$TMP_CHLOG_BAD" && bash "$RELEASE_SCRIPT" --test-changelog-insert 9.9.9 >/dev/null 2>&1); then
    fail "release.sh --test-changelog-insert: header-less fixture must exit non-zero"
  else
    pass "release.sh --test-changelog-insert: header-less fixture exits non-zero"
  fi
  BAD_AFTER="$(wc -c < "$TMP_CHLOG_BAD/CHANGELOG.md" | tr -d ' ')"
  if [[ "$BAD_BEFORE" == "$BAD_AFTER" ]]; then
    pass "release.sh --test-changelog-insert: header-less fixture left unchanged on refusal"
  else
    fail "release.sh --test-changelog-insert: header-less fixture corrupted ($BAD_BEFORE → $BAD_AFTER bytes)"
  fi
  rm -rf "$TMP_CHLOG_BAD"

  # Source-grep sentinel: the --test-changelog-insert flag must stay
  # wired in release.sh so a future refactor that drops it trips the
  # harness immediately.
  if grep -q '\-\-test-changelog-insert' "$RELEASE_SCRIPT"; then
    pass "release.sh defines --test-changelog-insert flag"
  else
    fail "release.sh defines --test-changelog-insert flag"
  fi
  if grep -q 'insert_changelog_entry()' "$RELEASE_SCRIPT"; then
    pass "release.sh exposes insert_changelog_entry() helper"
  else
    fail "release.sh exposes insert_changelog_entry() helper"
  fi
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
echo "== [S5-D] Next.js demo layout =="

# S5-05 — examples/nextjs-demo/ must mirror the examples/demo-app/
# layout, targeted at a Next.js 14 app-router project. File presence
# + config domain + PRD family declarations + pre-baked artifact
# verdicts are all asserted here so a future refactor can't silently
# delete half the demo and still pass CI.
NEXTJS_DEMO="$REPO_ROOT/examples/nextjs-demo"
NEXTJS_REQUIRED=(
  "README.md"
  ".gitignore"
  "vibeflow.config.json"
  "package.json"
  "tsconfig.json"
  "vitest.config.ts"
  "next.config.mjs"
  "docs/PRD.md"
  "docs/NEXTJS-DEMO-WALKTHROUGH.md"
  "app/layout.tsx"
  "app/page.tsx"
  "app/products/page.tsx"
  "app/products/[id]/page.tsx"
  "lib/catalog.ts"
  "lib/reviews.ts"
  "actions/submit-review.ts"
  "tests/catalog.test.ts"
  "tests/reviews.test.ts"
  "tests/action.test.ts"
  ".vibeflow/reports/prd-quality-report.md"
  ".vibeflow/reports/scenario-set.md"
  ".vibeflow/reports/test-strategy.md"
  ".vibeflow/reports/release-decision.md"
)
for rel in "${NEXTJS_REQUIRED[@]}"; do
  if [[ -f "$NEXTJS_DEMO/$rel" ]]; then
    pass "nextjs-demo: $rel present"
  else
    fail "nextjs-demo: $rel present"
  fi
done

# vibeflow.config.json must declare the e-commerce domain + list the
# Next.js-specific critical paths — the demo's PRD and
# release-decision weights depend on both.
if [[ -f "$NEXTJS_DEMO/vibeflow.config.json" ]]; then
  if jq -e '.domain == "e-commerce"' "$NEXTJS_DEMO/vibeflow.config.json" >/dev/null 2>&1; then
    pass "nextjs-demo: config domain is e-commerce"
  else
    fail "nextjs-demo: config domain is e-commerce"
  fi
  if jq -e '.criticalPaths | index("lib/reviews.ts") != null' "$NEXTJS_DEMO/vibeflow.config.json" >/dev/null 2>&1; then
    pass "nextjs-demo: lib/reviews.ts declared as a critical path"
  else
    fail "nextjs-demo: lib/reviews.ts declared as a critical path"
  fi
  if jq -e '.criticalPaths | index("actions/submit-review.ts") != null' "$NEXTJS_DEMO/vibeflow.config.json" >/dev/null 2>&1; then
    pass "nextjs-demo: actions/submit-review.ts declared as a critical path"
  else
    fail "nextjs-demo: actions/submit-review.ts declared as a critical path"
  fi
fi

# PRD must name every requirement family (PROD/REV/ACT/PAGE) so the
# rest of the pipeline has something to map onto.
if [[ -f "$NEXTJS_DEMO/docs/PRD.md" ]]; then
  for fam in PROD-001 PROD-004 REV-001 REV-004 ACT-001 ACT-003 PAGE-001 PAGE-002; do
    if grep -q "$fam" "$NEXTJS_DEMO/docs/PRD.md"; then
      pass "nextjs-demo PRD declares $fam"
    else
      fail "nextjs-demo PRD declares $fam"
    fi
  done
fi

# The server action file must start with the "use server" directive
# — a Next.js 14 requirement. Without it the <form action> wiring
# would fall back to client-side submission and the whole point of
# the demo (server actions) would silently regress.
if [[ -f "$NEXTJS_DEMO/actions/submit-review.ts" ]]; then
  if head -1 "$NEXTJS_DEMO/actions/submit-review.ts" | grep -q '"use server"'; then
    pass "nextjs-demo: submit-review.ts starts with \"use server\" directive"
  else
    fail "nextjs-demo: submit-review.ts starts with \"use server\" directive"
  fi
fi

# The product detail page must import notFound from next/navigation
# and call it when the product is undefined. PAGE-002.
DETAIL_PAGE="$NEXTJS_DEMO/app/products/[id]/page.tsx"
if [[ -f "$DETAIL_PAGE" ]]; then
  if grep -q 'from "next/navigation"' "$DETAIL_PAGE" && grep -q 'notFound()' "$DETAIL_PAGE"; then
    pass "nextjs-demo: detail page wires notFound() for unknown products"
  else
    fail "nextjs-demo: detail page wires notFound() for unknown products"
  fi
  if grep -q 'submitReviewAction' "$DETAIL_PAGE"; then
    pass "nextjs-demo: detail page wires submitReviewAction as the form handler"
  else
    fail "nextjs-demo: detail page wires submitReviewAction as the form handler"
  fi
fi

# The products listing page must import + call listProducts(). PAGE-001.
LIST_PAGE="$NEXTJS_DEMO/app/products/page.tsx"
if [[ -f "$LIST_PAGE" ]]; then
  if grep -q 'listProducts' "$LIST_PAGE"; then
    pass "nextjs-demo: listing page renders via listProducts()"
  else
    fail "nextjs-demo: listing page renders via listProducts()"
  fi
fi

# Pre-baked release decision must name a GO verdict with the composite
# score documented in the walkthrough. If a future edit changes the
# scoring without updating the harness, this fires.
if [[ -f "$NEXTJS_DEMO/.vibeflow/reports/release-decision.md" ]]; then
  if grep -q "GO — 91 / 100" "$NEXTJS_DEMO/.vibeflow/reports/release-decision.md"; then
    pass "nextjs-demo release-decision shows GO 91/100"
  else
    fail "nextjs-demo release-decision shows GO 91/100"
  fi
fi

# PRD quality report must document an APPROVED verdict above the
# e-commerce floor (75) so the demo walk-through makes sense.
if [[ -f "$NEXTJS_DEMO/.vibeflow/reports/prd-quality-report.md" ]]; then
  if grep -q "APPROVED" "$NEXTJS_DEMO/.vibeflow/reports/prd-quality-report.md"; then
    pass "nextjs-demo prd-quality report shows APPROVED"
  else
    fail "nextjs-demo prd-quality report shows APPROVED"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S5-E] Bug #13 cross-process reproducer (sprint-5 mirror) =="

# S5-06 [S5-E] — the same reproducer already guards run.sh [4]. We
# mirror it here so a future sprint that touches engine.getOrInit and
# skips run.sh (e.g. a contributor only runs sprint-5.sh because they
# only care about Sprint 5 work) still catches the regression.
#
# Flow (identical shape to run.sh [4], different project id + state.db
# directory so the two harnesses don't collide when run in parallel):
#   1. First engine invocation writes to the project — satisfy x2 +
#      record_consensus + advance REQUIREMENTS → DESIGN.
#   2. Second engine invocation calls sdlc_get_state on that same
#      project. Before the Sprint 4 fix to engine.getOrInit() this
#      path crashed with "revision must increment by exactly 1".
#   3. We assert the phase-2 response is NOT an error AND contains
#      the expected post-walk phase (DESIGN).

ENGINE_DIST_S5E="$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js"

if [[ ! -f "$ENGINE_DIST_S5E" ]]; then
  fail "[S5-E] sdlc-engine dist present at $ENGINE_DIST_S5E"
else
  pass "[S5-E] sdlc-engine dist present"

  S5E_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s5e-bug13-XXXXXX")"
  export VIBEFLOW_SQLITE_PATH="$S5E_DIR/state.db"
  export VIBEFLOW_PROJECT="s5e-bug13"
  export VIBEFLOW_MODE="solo"

  # Phase 1: writes — satisfy criteria, record consensus, advance to
  # DESIGN. The stdout/stderr are discarded; we only care about the
  # exit code and the side effect (state.db on disk).
  node "$ENGINE_DIST_S5E" >/dev/null 2>&1 <<'S5E_PHASE1'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s5e","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s5e-bug13","criterion":"prd.approved"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s5e-bug13","criterion":"testability.score>=60"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"s5e-bug13","phase":"REQUIREMENTS","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"s5e-bug13","to":"DESIGN"}}}
S5E_PHASE1
  S5E_PHASE1_RC=$?
  if (( S5E_PHASE1_RC == 0 )); then
    pass "[S5-E] phase-1 writes completed (engine exit 0)"
  else
    fail "[S5-E] phase-1 writes completed (engine exit $S5E_PHASE1_RC)"
  fi

  # state.db must exist on disk — proves the writes landed and that a
  # fresh process will see them.
  if [[ -f "$S5E_DIR/state.db" ]]; then
    pass "[S5-E] state.db persisted after phase-1 writes"
  else
    fail "[S5-E] state.db persisted after phase-1 writes"
  fi

  # Phase 2: a FRESH engine process calls get_state on the same
  # project. Before the Sprint 4 fix to engine.getOrInit() this
  # failed because getOrInit's transact() returned
  # `{ next: current, result: current }` on an existing row — same
  # revision — which tripped the mutator's "revision must increment
  # by exactly 1" assertion.
  S5E_OUT="$(node "$ENGINE_DIST_S5E" 2>/dev/null <<'S5E_PHASE2'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s5e-r","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"s5e-bug13"}}}
S5E_PHASE2
)"

  S5E_LINE="$(echo "$S5E_OUT" | grep '"id":2' || true)"
  if [[ -z "$S5E_LINE" ]]; then
    fail "[S5-E] phase-2 get_state produced no response"
  elif [[ "$S5E_LINE" == *'"isError":true'* ]]; then
    fail "[S5-E] phase-2 get_state returned an error envelope"
  elif [[ "$S5E_LINE" == *"revision must increment"* ]]; then
    fail "[S5-E] phase-2 get_state tripped the mutator revision check (Bug #13 regressed)"
  else
    pass "[S5-E] phase-2 get_state succeeds on an existing project"
  fi

  # The returned state must reflect the post-walk phase, DESIGN.
  # Without this, a future regression could silently return
  # REQUIREMENTS (the in-memory default) without tripping the
  # error-envelope check above.
  if [[ "$S5E_LINE" == *"DESIGN"* ]]; then
    pass "[S5-E] phase-2 get_state returns DESIGN after advance"
  else
    fail "[S5-E] phase-2 get_state returns DESIGN after advance"
  fi

  rm -rf "$S5E_DIR"
  unset VIBEFLOW_SQLITE_PATH VIBEFLOW_PROJECT VIBEFLOW_MODE
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
