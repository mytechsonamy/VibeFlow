#!/bin/bash
# VibeFlow Sprint 7 integration harness.
#
# Complements run.sh + sprint-2.sh + sprint-3.sh + sprint-4.sh +
# sprint-5.sh + sprint-6.sh. Sprint 7 targets v1.2.0 and picks up
# items deferred from Sprint 6's scope decisions + the two lessons
# captured during the v1.1.0 release (Sprint 6 / S6-09).
#
# Sections:
#   [S7-A] — release.sh pre-step-5 pg peer-dep sanity check (S7-04)
#   [S7-B] — docs/RELEASING.md troubleshooting + sha256-drift recovery (S7-05)
#   [S7-C] — Reproducible package-plugin.sh tarball (S7-05B)
#   [S7-D] — Self-hosted GitLab baseUrl plumbing (S7-01)
#   [S7-E] — Postgres version matrix PG13/14/15/16 (S7-02)
#   [S7-Z] — Sprint 7 harness self-audit (mirrors [S6-Z])
#
# Sprint 7 ticket coverage (as of current commit):
#   S7-01  (self-hosted GitLab)                  → [S7-D]
#   S7-02  (Postgres version matrix)             → [S7-E]
#   S7-04  (release.sh pg sanity check)          → [S7-A]
#   S7-05  (RELEASING.md troubleshooting)        → [S7-B]
#   S7-05B (reproducible package-plugin tarball) → [S7-C]
# S7-03 / S7-06 / S7-07 are not yet picked up — if and when they
# land, they will add their own [S7-F/…] sections here.
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S7-A] release.sh pre-step-5 pg peer-dep sanity check =="

# S7-04 — release.sh must refuse to proceed past step [0.5] if the
# pg peer dependency is not installed in sdlc-engine's node_modules.
# Without this check, the release fails mid-flight at step [5]
# (build-all.sh) with `Cannot find module 'pg'` AFTER plugin.json
# has been bumped — leaving the working tree in an awkward
# half-released state.
#
# These sentinels are source-grep checks. Exercising the actual
# failure path would require uninstalling pg, which would break the
# normal-dev build. The structural checks are enough: if the step
# [0.5] logic is present, it must fire when pg is actually missing
# (that's the `[[ ! -d ... ]] && exit 1` guarantee).

RELEASE_SCRIPT_S7A="$REPO_ROOT/bin/release.sh"

# The [0.5] section header must be present (it's the visible marker
# of the sanity check).
if grep -q '== \[0.5\] build-dependency sanity' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh has a [0.5] build-dependency sanity section"
else
  fail "[S7-A] release.sh has a [0.5] build-dependency sanity section"
fi

# The probe must name the exact path that build-all.sh requires —
# mcp-servers/sdlc-engine/node_modules/pg. Anything else would be
# a weaker check.
if grep -q 'mcp-servers/sdlc-engine/node_modules/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh probes sdlc-engine/node_modules/pg"
else
  fail "[S7-A] release.sh probes sdlc-engine/node_modules/pg"
fi

# The probe must ALSO include @types/pg — tsc needs both the
# runtime module and the types. Without the types, tsc fails with a
# different error (TS2307) that the bare pg check wouldn't catch.
if grep -q 'node_modules/@types/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh probes sdlc-engine/node_modules/@types/pg"
else
  fail "[S7-A] release.sh probes sdlc-engine/node_modules/@types/pg"
fi

# The error output must include the fix command so the maintainer
# doesn't have to hunt for it. `cd mcp-servers/sdlc-engine && npm install pg @types/pg`
# is a one-liner we print directly.
if grep -q 'npm install pg @types/pg' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh prints the 'npm install pg @types/pg' fix command"
else
  fail "[S7-A] release.sh prints the 'npm install pg @types/pg' fix command"
fi

# The sanity check must run BEFORE step [1] (version argument).
# Otherwise a pg-missing release would still bump plugin.json's
# version in step [3] before failing at step [5] — same half-
# released state the ticket is designed to prevent.
#
# grep -n gives us line numbers; we compare the [0.5] position
# against the [1] position.
LINE_05="$(grep -n '== \[0.5\]' "$RELEASE_SCRIPT_S7A" | head -1 | cut -d: -f1)"
LINE_1="$(grep -n '== \[1\] version argument' "$RELEASE_SCRIPT_S7A" | head -1 | cut -d: -f1)"
if [[ -n "$LINE_05" ]] && [[ -n "$LINE_1" ]] && (( LINE_05 < LINE_1 )); then
  pass "[S7-A] [0.5] sanity check runs before [1] version argument (line $LINE_05 < $LINE_1)"
else
  fail "[S7-A] [0.5] sanity check runs before [1] version argument (got 0.5=$LINE_05 1=$LINE_1)"
fi

# The S7-04 ticket reference must appear in the section comment so
# a future contributor reading the code knows why the check exists.
if grep -q 'S7-04' "$RELEASE_SCRIPT_S7A"; then
  pass "[S7-A] release.sh [0.5] section cites S7-04 in the comment"
else
  fail "[S7-A] release.sh [0.5] section cites S7-04 in the comment"
fi

# ---------------------------------------------------------------------------
echo "== [S7-B] RELEASING.md troubleshooting + sha256-drift recovery =="

# S7-05 — docs/RELEASING.md must document the two recovery paths
# that surfaced during the v1.1.0 release:
#   1. pg peer dep missing → step [5] fails
#   2. sha256 sidecar drift after preflight regenerates the tarball
# Without these entries, a future maintainer hitting the same
# incident has to rediscover the fix from scratch.

RELEASING_DOC_S7B="$REPO_ROOT/docs/RELEASING.md"

if [[ -f "$RELEASING_DOC_S7B" ]]; then
  # Troubleshooting entry 1 — pg peer dep missing. Must mention
  # the error text ("Cannot find module 'pg'") OR the new
  # release.sh message ("pg peer dep is not installed") so a
  # maintainer searching either text finds the entry.
  if grep -q "pg peer dep is not installed" "$RELEASING_DOC_S7B" \
      || grep -q "Cannot find module 'pg'" "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the pg peer-dep-missing error"
  else
    fail "[S7-B] RELEASING.md documents the pg peer-dep-missing error"
  fi
  # The entry must surface the one-liner fix so the maintainer
  # doesn't have to dig.
  if grep -q 'npm install pg @types/pg' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md surfaces the 'npm install pg @types/pg' fix"
  else
    fail "[S7-B] RELEASING.md surfaces the 'npm install pg @types/pg' fix"
  fi

  # Troubleshooting entry 2 — mid-flight release failure recovery.
  # Must cover the manual re-run of build-all.sh + package-plugin.sh
  # + sha256 regeneration.
  if grep -q 'release.sh fails MID-FLIGHT' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the mid-flight failure recovery"
  else
    fail "[S7-B] RELEASING.md documents the mid-flight failure recovery"
  fi

  # Troubleshooting entry 3 — sha256 drift. Must describe the
  # root cause (preflight regenerates tarball) + the fix (regen
  # + gh release upload --clobber).
  if grep -q 'sha256 sidecar' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md documents the sha256 sidecar drift"
  else
    fail "[S7-B] RELEASING.md documents the sha256 sidecar drift"
  fi
  if grep -q 'gh release upload.*--clobber' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md includes the 'gh release upload --clobber' fix"
  else
    fail "[S7-B] RELEASING.md includes the 'gh release upload --clobber' fix"
  fi
  # The root-cause note must mention sprint-4.sh [S4-G] so future
  # readers know why the tarball regenerates and can reason about
  # whether it still applies.
  if grep -q 'sprint-4.sh \[S4-G\]' "$RELEASING_DOC_S7B"; then
    pass "[S7-B] RELEASING.md attributes tarball regen to sprint-4.sh [S4-G]"
  else
    fail "[S7-B] RELEASING.md attributes tarball regen to sprint-4.sh [S4-G]"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S7-C] Reproducible package-plugin.sh tarball =="

# S7-05B — package-plugin.sh must produce byte-identical tarballs
# on consecutive runs against the same input tree. This closes the
# sha256 drift surface that bit Sprint 6 / S6-09 (v1.1.0 release):
# the sidecar generated by release.sh's step [6] stopped matching
# the archive that ended up on GitHub because the preflight
# gauntlet at sprint-4.sh [S4-G] re-ran package-plugin.sh a second
# time, producing a tarball with different mtimes baked in.
#
# Four source-grep sentinels verify the determinism plumbing is
# present, plus one RUNTIME sentinel that actually runs
# package-plugin.sh twice and asserts the sha256 matches. The
# runtime sentinel is the real guarantee — the source-greps are
# a safety net catching accidental deletions.

PACKAGE_SCRIPT_S7C="$REPO_ROOT/package-plugin.sh"

# 1. gzip -n is the essential flag — without it the gzip header
#    contains a filename + timestamp that differs per run.
if grep -q 'gzip -n' "$PACKAGE_SCRIPT_S7C"; then
  pass "[S7-C] package-plugin.sh pipes through 'gzip -n' (strips gzip timestamp)"
else
  fail "[S7-C] package-plugin.sh pipes through 'gzip -n'"
fi

# 2. mtime normalization — the staging dir gets its file mtimes
#    zeroed out before tarring.
if grep -q 'touch -t 197001010000' "$PACKAGE_SCRIPT_S7C"; then
  pass "[S7-C] package-plugin.sh normalizes staged file mtimes to epoch 0"
else
  fail "[S7-C] package-plugin.sh normalizes staged file mtimes to epoch 0"
fi

# 3. Sorted file list — tar -T processes entries in the order
#    given; unsorted input (from find) varies across runs.
if grep -q 'sort "\$TMPLIST"' "$PACKAGE_SCRIPT_S7C"; then
  pass "[S7-C] package-plugin.sh sorts the file list before tarring"
else
  fail "[S7-C] package-plugin.sh sorts the file list before tarring"
fi

# 4. tar variant detection — BSD tar (macOS) uses --uid/--gid,
#    GNU tar (Linux) uses --owner/--group. Cross-platform
#    reproducibility requires detecting the variant.
if grep -q 'bsdtar\\\\|libarchive' "$PACKAGE_SCRIPT_S7C" \
    || grep -q '"bsdtar\|libarchive"' "$PACKAGE_SCRIPT_S7C"; then
  pass "[S7-C] package-plugin.sh detects bsdtar vs GNU tar for ownership flags"
else
  fail "[S7-C] package-plugin.sh detects bsdtar vs GNU tar for ownership flags"
fi

# 5. S7-05B reference in the code comment so a future contributor
#    can trace back to this ticket when reading package-plugin.sh.
if grep -q 'S7-05B' "$PACKAGE_SCRIPT_S7C"; then
  pass "[S7-C] package-plugin.sh cites S7-05B in the comment"
else
  fail "[S7-C] package-plugin.sh cites S7-05B in the comment"
fi

# 6. RUNTIME — the real guarantee. Run package-plugin.sh twice
#    against the current tree, compare sha256. Must be byte-
#    identical. Uses a separate tempdir so we don't clobber any
#    tarball the user has sitting in the repo root. Skipped when
#    the repo is dirty (the cleanliness check in release.sh +
#    user-not-wanting-to-have-artifacts-rebuilt heuristic).
DETERMINISM_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s7c-det.XXXXXX")"
SAVED_DIR="$DETERMINISM_TMPDIR/saved"
mkdir -p "$SAVED_DIR"

# Sprint 8 / S8-02 — save/restore EVERY pre-existing tarball +
# sidecar. The old logic used `ls | head -1` to pick one tarball
# but `rm -f vibeflow-plugin-*.tar.gz` deleted all of them. When
# the harness ran right after a fresh `release.sh <new-version>`
# produced v<new>.tar.gz on top of a stale v<old>.tar.gz, only
# v<old> got saved and v<new> was clobbered — exactly what bit
# the v1.2.0 release during S7-07. Fix: `mv` every matching file
# into $SAVED_DIR on entry, `mv` every file in $SAVED_DIR back
# on exit. `shopt -s nullglob` is too big a hammer (would leak
# into later sections); we use a for-loop + `[[ -e ]]` guard
# instead so the glob expands to nothing-useful silently.
for f in "$REPO_ROOT"/vibeflow-plugin-*.tar.gz \
         "$REPO_ROOT"/vibeflow-plugin-*.tar.gz.sha256; do
  [[ -e "$f" ]] || continue
  mv "$f" "$SAVED_DIR/"
done

# Run 1 + run 2. Suppress stdout but capture failures.
if (cd "$REPO_ROOT" && bash package-plugin.sh --skip-build >/dev/null 2>&1); then
  SHA_RUN1="$(shasum -a 256 "$REPO_ROOT"/vibeflow-plugin-*.tar.gz | awk '{print $1}')"
  # Move run1 output out of the way so run2 produces a fresh file.
  mv "$REPO_ROOT"/vibeflow-plugin-*.tar.gz "$DETERMINISM_TMPDIR/run1.tar.gz"

  if (cd "$REPO_ROOT" && bash package-plugin.sh --skip-build >/dev/null 2>&1); then
    SHA_RUN2="$(shasum -a 256 "$REPO_ROOT"/vibeflow-plugin-*.tar.gz | awk '{print $1}')"
    if [[ "$SHA_RUN1" == "$SHA_RUN2" ]]; then
      pass "[S7-C] package-plugin.sh produces byte-identical tarballs on consecutive runs"
    else
      fail "[S7-C] package-plugin.sh produces byte-identical tarballs (run1=$SHA_RUN1 run2=$SHA_RUN2)"
    fi
  else
    fail "[S7-C] package-plugin.sh run 2 failed"
  fi
  rm -f "$REPO_ROOT"/vibeflow-plugin-*.tar.gz
else
  fail "[S7-C] package-plugin.sh run 1 failed"
fi

# Sprint 8 / S8-02 — restore EVERY saved file. The `[[ -e ]]`
# guard handles the empty-saved-dir case (nothing to restore, the
# glob expands to a non-existent literal and the loop body skips).
for f in "$SAVED_DIR"/vibeflow-plugin-*.tar.gz \
         "$SAVED_DIR"/vibeflow-plugin-*.tar.gz.sha256; do
  [[ -e "$f" ]] || continue
  mv "$f" "$REPO_ROOT/"
done
rm -rf "$DETERMINISM_TMPDIR"

# ---------------------------------------------------------------------------
echo "== [S7-D] Self-hosted GitLab baseUrl plumbing =="

# S7-01 — self-hosted GitLab instances configure a custom API host
# via `userConfig.gitlab_base_url`. The client accepted the option
# from day one, but the plumbing (plugin manifest → .mcp.json env
# var → dev-ops tools.ts → createGitlabClient) was never fully
# wired. S7-01 closes every gap + adds test coverage.
#
# Sentinels verify each link of the chain so a future refactor that
# breaks any step trips immediately.

DEV_OPS_CLIENT_S7D="$REPO_ROOT/mcp-servers/dev-ops/src/client.ts"
DEV_OPS_TOOLS_S7D="$REPO_ROOT/mcp-servers/dev-ops/src/tools.ts"
DEV_OPS_TEST_S7D="$REPO_ROOT/mcp-servers/dev-ops/tests/gitlab-client.test.ts"
PLUGIN_MANIFEST_S7D="$REPO_ROOT/.claude-plugin/plugin.json"
MCP_CONFIG_S7D="$REPO_ROOT/.mcp.json"
CONFIG_DOC_S7D="$REPO_ROOT/docs/CONFIGURATION.md"

# 1. Plugin manifest declares gitlab_base_url in userConfig.
if jq -e '.userConfig | has("gitlab_base_url")' "$PLUGIN_MANIFEST_S7D" >/dev/null 2>&1; then
  pass "[S7-D] plugin.json userConfig declares gitlab_base_url"
else
  fail "[S7-D] plugin.json userConfig declares gitlab_base_url"
fi

# 2. Plugin manifest declares gitlab_token as sensitive.
if jq -e '.userConfig.gitlab_token.sensitive == true' "$PLUGIN_MANIFEST_S7D" >/dev/null 2>&1; then
  pass "[S7-D] plugin.json userConfig declares gitlab_token as sensitive"
else
  fail "[S7-D] plugin.json userConfig declares gitlab_token as sensitive"
fi

# 3. .mcp.json passes GITLAB_BASE_URL env from userConfig.gitlab_base_url.
if grep -q '"GITLAB_BASE_URL": "\${userConfig.gitlab_base_url}"' "$MCP_CONFIG_S7D"; then
  pass "[S7-D] .mcp.json wires GITLAB_BASE_URL from userConfig.gitlab_base_url"
else
  fail "[S7-D] .mcp.json wires GITLAB_BASE_URL from userConfig.gitlab_base_url"
fi

# 4. .mcp.json passes GITLAB_TOKEN env from userConfig.gitlab_token.
if grep -q '"GITLAB_TOKEN": "\${userConfig.gitlab_token}"' "$MCP_CONFIG_S7D"; then
  pass "[S7-D] .mcp.json wires GITLAB_TOKEN from userConfig.gitlab_token"
else
  fail "[S7-D] .mcp.json wires GITLAB_TOKEN from userConfig.gitlab_token"
fi

# 5. dev-ops tools.ts reads process.env.GITLAB_BASE_URL as the
#    baseUrl fallback when ci_provider=gitlab. Without this read,
#    the env var is set but never consumed.
if grep -q 'process.env.GITLAB_BASE_URL' "$DEV_OPS_TOOLS_S7D"; then
  pass "[S7-D] dev-ops tools.ts reads process.env.GITLAB_BASE_URL"
else
  fail "[S7-D] dev-ops tools.ts reads process.env.GITLAB_BASE_URL"
fi

# 6. createGitlabClient treats empty-string baseUrl as "use default".
#    Plugin userConfig values are strings; unset keys arrive as "".
#    Without this coercion, a user who hasn't set gitlab_base_url
#    would send requests to an empty host.
if grep -q 'baseUrl.length > 0' "$DEV_OPS_CLIENT_S7D" \
    || grep -q 'opts.baseUrl &&.*baseUrl.length' "$DEV_OPS_CLIENT_S7D"; then
  pass "[S7-D] createGitlabClient coerces empty-string baseUrl to the default"
else
  fail "[S7-D] createGitlabClient coerces empty-string baseUrl to the default"
fi

# 7. gitlab-client.test.ts has the self-hosted baseUrl describe
#    block.
if grep -q "self-hosted baseUrl (S7-01)" "$DEV_OPS_TEST_S7D"; then
  pass "[S7-D] gitlab-client.test.ts has the S7-01 self-hosted describe block"
else
  fail "[S7-D] gitlab-client.test.ts has the S7-01 self-hosted describe block"
fi

# 8. The test block must exercise at least one non-gitlab.com URL
#    so we know the baseUrl is actually flowing to the fetch impl.
if grep -q "gitlab.example.com/api/v4" "$DEV_OPS_TEST_S7D"; then
  pass "[S7-D] gitlab-client.test.ts exercises a custom host URL"
else
  fail "[S7-D] gitlab-client.test.ts exercises a custom host URL"
fi

# 9. CONFIGURATION.md documents the new userConfig keys so users
#    actually know the self-hosted option exists. Without docs, a
#    self-hosted-GitLab user might never know to set it.
if [[ -f "$CONFIG_DOC_S7D" ]]; then
  if grep -q 'gitlab_base_url' "$CONFIG_DOC_S7D"; then
    pass "[S7-D] CONFIGURATION.md documents gitlab_base_url"
  else
    fail "[S7-D] CONFIGURATION.md documents gitlab_base_url"
  fi
  if grep -q 'gitlab_token' "$CONFIG_DOC_S7D"; then
    pass "[S7-D] CONFIGURATION.md documents gitlab_token"
  else
    fail "[S7-D] CONFIGURATION.md documents gitlab_token"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S7-E] Postgres version matrix (PG13/14/15/16) =="

# S7-02 — Sprint 5 / S5-03 shipped the first live-Postgres test but
# pinned postgres:14-alpine. Sprint 6 / S6-01's concurrent-CAS
# stress test kept the same pin. Real users run a mix of PG13
# through PG16 + managed-cloud variants. S7-02 parameterizes
# bin/with-postgres.sh into a matrix runner so we can smoke-test
# the engine's state store against every Postgres version inside
# the supported window.
#
# Structural sentinels always run; the live matrix run is opt-in
# via VF_RUN_PG_MATRIX=1 because it spins up 4 containers
# sequentially (~3 minutes on this hardware). The default gauntlet
# skips the matrix to keep release.sh preflight under 5 minutes.

MATRIX_SCRIPT_S7E="$REPO_ROOT/bin/with-postgres-matrix.sh"
TEAM_MODE_DOC_S7E="$REPO_ROOT/docs/TEAM-MODE.md"

# 1. Matrix runner file exists + is executable.
if [[ -f "$MATRIX_SCRIPT_S7E" ]] && [[ -x "$MATRIX_SCRIPT_S7E" ]]; then
  pass "[S7-E] bin/with-postgres-matrix.sh present + executable"
else
  fail "[S7-E] bin/with-postgres-matrix.sh present + executable"
fi

# 2-5. Default image list must cover PG13 / PG14 / PG15 / PG16.
# Narrowing the matrix is the user's call (VF_PG_IMAGES override);
# the default must be the full supported window so a fresh run
# catches version-specific breakage. Each check greps for the
# image tag separately so missing any one fires a distinct failure.
if [[ -f "$MATRIX_SCRIPT_S7E" ]]; then
  for pg_tag in "postgres:13-alpine" "postgres:14-alpine" "postgres:15-alpine" "postgres:16-alpine"; do
    if grep -q "$pg_tag" "$MATRIX_SCRIPT_S7E"; then
      pass "[S7-E] default matrix includes $pg_tag"
    else
      fail "[S7-E] default matrix includes $pg_tag"
    fi
  done
fi

# 6. Matrix runner must delegate per-image work to the existing
#    with-postgres.sh wrapper. Duplicating the docker-pull +
#    pg_isready + cleanup logic inside the matrix would be a
#    maintenance nightmare.
if [[ -f "$MATRIX_SCRIPT_S7E" ]]; then
  if grep -q 'bash "\$WRAPPER"' "$MATRIX_SCRIPT_S7E" \
      || grep -q 'bin/with-postgres.sh' "$MATRIX_SCRIPT_S7E"; then
    pass "[S7-E] matrix runner delegates to bin/with-postgres.sh per image"
  else
    fail "[S7-E] matrix runner delegates to bin/with-postgres.sh per image"
  fi
fi

# 7. sprint-5.sh [S5-B] and sprint-6.sh [S6-A] must compose with
#    the matrix by reusing DATABASE_URL when it's set externally.
#    Without this, nested with-postgres.sh invocations collide on
#    port 55432 and every matrix iteration fails.
if grep -q 'DATABASE_URL.*]]; then' "$REPO_ROOT/tests/integration/sprint-5.sh"; then
  pass "[S7-E] sprint-5.sh [S5-B] reuses outer DATABASE_URL when set"
else
  fail "[S7-E] sprint-5.sh [S5-B] reuses outer DATABASE_URL when set"
fi
if grep -q 'DATABASE_URL.*]]; then' "$REPO_ROOT/tests/integration/sprint-6.sh"; then
  pass "[S7-E] sprint-6.sh [S6-A] reuses outer DATABASE_URL when set"
else
  fail "[S7-E] sprint-6.sh [S6-A] reuses outer DATABASE_URL when set"
fi

# 8. TEAM-MODE.md documents the supported-versions window.
if grep -q "Supported Postgres versions" "$TEAM_MODE_DOC_S7E"; then
  pass "[S7-E] TEAM-MODE.md documents the supported Postgres versions"
else
  fail "[S7-E] TEAM-MODE.md documents the supported Postgres versions"
fi

# 9. TEAM-MODE.md documents managed-cloud caveats (RDS/Cloud SQL/Azure).
if grep -q "Managed-cloud Postgres" "$TEAM_MODE_DOC_S7E"; then
  pass "[S7-E] TEAM-MODE.md documents managed-cloud Postgres caveats"
else
  fail "[S7-E] TEAM-MODE.md documents managed-cloud Postgres caveats"
fi

# 10. Managed-cloud section must call out the PgBouncer transaction-
#     pool issue with advisory locks. This is the non-obvious
#     gotcha — managed Postgres behind transaction-mode PgBouncer
#     silently breaks VibeFlow's CAS serialization.
if grep -q "PgBouncer" "$TEAM_MODE_DOC_S7E"; then
  pass "[S7-E] TEAM-MODE.md calls out the PgBouncer transaction-mode caveat"
else
  fail "[S7-E] TEAM-MODE.md calls out the PgBouncer transaction-mode caveat"
fi

# 11. sslmode=require note for RDS/Cloud SQL — the most common
#     failure mode when a managed-Postgres user first tries to
#     connect.
if grep -q "sslmode=require" "$TEAM_MODE_DOC_S7E"; then
  pass "[S7-E] TEAM-MODE.md documents the sslmode=require requirement"
else
  fail "[S7-E] TEAM-MODE.md documents the sslmode=require requirement"
fi

# 12. RUNTIME (opt-in) — actually run the matrix end-to-end.
#     Opt-in via VF_RUN_PG_MATRIX=1 because the run takes ~3 min
#     and pulls 4 docker images (~400 MB cumulative first run).
#     Honors the same VF_SKIP_LIVE_POSTGRES + docker-daemon probes
#     as [S5-B] and [S6-A].
if [[ "${VF_RUN_PG_MATRIX:-}" != "1" ]]; then
  pass "[S7-E] live matrix run skipped (opt-in via VF_RUN_PG_MATRIX=1)"
elif [[ "${VF_SKIP_LIVE_POSTGRES:-}" == "1" ]]; then
  pass "[S7-E] live matrix run skipped via VF_SKIP_LIVE_POSTGRES=1"
elif ! command -v docker >/dev/null 2>&1; then
  pass "[S7-E] live matrix run skipped — docker binary not installed"
elif ! docker info >/dev/null 2>&1; then
  pass "[S7-E] live matrix run skipped — docker daemon not running"
elif [[ ! -d "$REPO_ROOT/mcp-servers/sdlc-engine/node_modules/pg" ]]; then
  pass "[S7-E] live matrix run skipped — pg optional peer dep not installed"
else
  # Run the matrix against sprint-5.sh which includes [S5-B]. Each
  # image gets its own fresh container via the matrix wrapper.
  if bash "$MATRIX_SCRIPT_S7E" bash "$REPO_ROOT/tests/integration/sprint-5.sh" >/tmp/vf-s7e-matrix.log 2>&1; then
    pass "[S7-E] live matrix run — all 4 PG versions pass the S5-B walk"
  else
    fail "[S7-E] live matrix run — at least one PG version failed"
    echo "    matrix log tail:" >&2
    tail -15 /tmp/vf-s7e-matrix.log >&2 || true
  fi
  rm -f /tmp/vf-s7e-matrix.log
fi

# ---------------------------------------------------------------------------
echo "== [S7-Z] sprint-7.sh harness self-audit =="

# Mirrors sprint-6.sh [S6-Z]. Catches section-deletion, chmod -x,
# missing release.sh preflight entry, bad shebang, and missing
# set -uo pipefail — regressions a future refactor might introduce
# without firing any other harness.

SELF_S7Z="$REPO_ROOT/tests/integration/sprint-7.sh"

# 1-6. Each expected section header must still be present.
for sec_label in "S7-A" "S7-B" "S7-C" "S7-D" "S7-E" "S7-Z"; do
  if grep -q "echo \"== \[$sec_label\]" "$SELF_S7Z"; then
    pass "[S7-Z] [$sec_label] section header still present"
  else
    fail "[S7-Z] [$sec_label] section header still present"
  fi
done

# 4. Harness file must still be executable.
if [[ -x "$SELF_S7Z" ]]; then
  pass "[S7-Z] sprint-7.sh is executable"
else
  fail "[S7-Z] sprint-7.sh is executable"
fi

# 5. bin/release.sh preflight must reference sprint-7.sh.
if grep -q 'tests/integration/sprint-7.sh' "$REPO_ROOT/bin/release.sh"; then
  pass "[S7-Z] bin/release.sh preflight references sprint-7.sh"
else
  fail "[S7-Z] bin/release.sh preflight references sprint-7.sh"
fi

# 6. Shebang is #!/bin/bash.
if head -1 "$SELF_S7Z" | grep -q '^#!/bin/bash$'; then
  pass "[S7-Z] sprint-7.sh shebang is #!/bin/bash"
else
  fail "[S7-Z] sprint-7.sh shebang is #!/bin/bash"
fi

# 7. set -uo pipefail in effect.
if grep -q '^set -uo pipefail$' "$SELF_S7Z"; then
  pass "[S7-Z] sprint-7.sh runs under set -uo pipefail"
else
  fail "[S7-Z] sprint-7.sh runs under set -uo pipefail"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
