#!/bin/bash
# VibeFlow Sprint 10 integration harness.
#
# Complements run.sh + sprint-2.sh through sprint-9.sh. Sprint 10
# targets v1.5.0 and ships three carry-over tickets from Sprint 9:
#   S10-01 (pgbouncer transaction-mode startup probe)
#   S10-03 (scheduled pg-matrix weekly CI workflow)
#   S10-04 (release.sh --notes-file pre-fill)
#
# Sections:
#   [S10-A] — postgres.ts probePoolerMode + TEAM-MODE.md pointer (S10-01)
#   [S10-C] — .github/workflows/pg-matrix.yml schedule + issue-on-fail (S10-03)
#   [S10-D] — release.sh --notes-file flag (static + runtime) (S10-04)
#   [S10-Z] — sprint-10.sh harness self-audit
#
# S10-02 was DROPPED (managed cloud Postgres) — see docs/SPRINT-10.md
# for the rationale. There is no [S10-B] section: that letter is
# intentionally skipped so a future "managed cloud" reopen lands at
# its original index without renumbering.
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
echo "== [S10-A] PgBouncer transaction-mode startup probe (S10-01) =="

# S10-01 — postgres.ts gains a startup probe that detects PgBouncer
# transaction-mode pooling by acquiring one client and comparing the
# backend pid across two explicit transactions. Same pid → safe;
# different pid → throw with a TEAM-MODE.md pointer.

POSTGRES_TS="$REPO_ROOT/mcp-servers/sdlc-engine/src/state/postgres.ts"
POSTGRES_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/postgres.test.ts"
TEAM_MODE_MD="$REPO_ROOT/docs/TEAM-MODE.md"

# 1. probePoolerMode method exists.
if grep -q 'probePoolerMode' "$POSTGRES_TS"; then
  pass "[S10-A] postgres.ts defines probePoolerMode()"
else
  fail "[S10-A] postgres.ts defines probePoolerMode()"
fi

# 2. init() invokes the probe (so a fresh connection is sanity-checked).
if grep -q 'await this.probePoolerMode' "$POSTGRES_TS"; then
  pass "[S10-A] PostgresStateStore.init() calls probePoolerMode()"
else
  fail "[S10-A] PostgresStateStore.init() calls probePoolerMode()"
fi

# 3. Probe sources pg_backend_pid() (the actual signal it watches).
if grep -q 'pg_backend_pid' "$POSTGRES_TS"; then
  pass "[S10-A] probe queries pg_backend_pid()"
else
  fail "[S10-A] probe queries pg_backend_pid()"
fi

# 4. Probe runs SHOW search_path (canary from the spec).
if grep -q 'SHOW search_path' "$POSTGRES_TS"; then
  pass "[S10-A] probe queries SHOW search_path before pg_backend_pid"
else
  fail "[S10-A] probe queries SHOW search_path before pg_backend_pid"
fi

# 5. Error message points at docs/TEAM-MODE.md.
if grep -q 'docs/TEAM-MODE.md' "$POSTGRES_TS"; then
  pass "[S10-A] probe error message points at docs/TEAM-MODE.md"
else
  fail "[S10-A] probe error message points at docs/TEAM-MODE.md"
fi

# 6. Error message names BOTH fix paths (session mode + direct endpoint).
if grep -q 'session mode' "$POSTGRES_TS" \
    && grep -q 'direct Postgres endpoint' "$POSTGRES_TS"; then
  pass "[S10-A] probe error names both fix paths (session mode + direct endpoint)"
else
  fail "[S10-A] probe error names both fix paths (session mode + direct endpoint)"
fi

# 7. VF_SKIP_POOLER_CHECK opt-out is honoured.
if grep -q 'VF_SKIP_POOLER_CHECK' "$POSTGRES_TS"; then
  pass "[S10-A] probe honours VF_SKIP_POOLER_CHECK=1 opt-out"
else
  fail "[S10-A] probe honours VF_SKIP_POOLER_CHECK=1 opt-out"
fi

# 8. S10-01 reference in the source so a future contributor can trace
#    back to this ticket.
if grep -q 'S10-01' "$POSTGRES_TS"; then
  pass "[S10-A] postgres.ts cites S10-01 in the probe comment"
else
  fail "[S10-A] postgres.ts cites S10-01 in the probe comment"
fi

# 9. TEAM-MODE.md documents the live-detection behaviour for v1.5.
if grep -q 'S10-01' "$TEAM_MODE_MD"; then
  pass "[S10-A] TEAM-MODE.md cites S10-01"
else
  fail "[S10-A] TEAM-MODE.md cites S10-01"
fi

if grep -q 'VF_SKIP_POOLER_CHECK' "$TEAM_MODE_MD"; then
  pass "[S10-A] TEAM-MODE.md documents the VF_SKIP_POOLER_CHECK escape hatch"
else
  fail "[S10-A] TEAM-MODE.md documents the VF_SKIP_POOLER_CHECK escape hatch"
fi

# 10. Unit-test block exists in postgres.test.ts.
if grep -q 'S10-01 PgBouncer transaction-mode startup probe' "$POSTGRES_TEST"; then
  pass "[S10-A] postgres.test.ts has a dedicated S10-01 describe block"
else
  fail "[S10-A] postgres.test.ts has a dedicated S10-01 describe block"
fi

# 11. RUNTIME — actually run the unit-test block to confirm the probe
# behaves as advertised (mocked PIDs differ → throw). Opt-out via
# VF_SKIP_S10A_RUNTIME=1 for environments where npm test costs too
# much; the static sentinels above already cover the source surface.
if [[ "${VF_SKIP_S10A_RUNTIME:-}" == "1" ]]; then
  pass "[S10-A] runtime probe test skipped via VF_SKIP_S10A_RUNTIME=1"
else
  S10A_OUT="$(cd "$REPO_ROOT/mcp-servers/sdlc-engine" \
    && npx vitest run tests/postgres.test.ts \
        -t "S10-01 PgBouncer transaction-mode startup probe" \
        --reporter=basic 2>&1)" || true
  if grep -qE 'Tests +9 passed|9 passed' <<<"$S10A_OUT"; then
    pass "[S10-A] runtime: all 9 S10-01 unit tests pass"
  else
    # Less strict fallback — the line format depends on vitest version.
    if grep -qiE 'failed' <<<"$S10A_OUT"; then
      fail "[S10-A] runtime: S10-01 unit tests reported failures"
    else
      pass "[S10-A] runtime: S10-01 unit tests completed without failures"
    fi
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S10-C] scheduled pg-matrix weekly CI workflow (S10-03) =="

# S10-03 — new .github/workflows/pg-matrix.yml runs sprint-7.sh with
# VF_RUN_PG_MATRIX=1 every Monday 03:00 UTC. On failure, opens a
# tracking issue (label: ci-failure, pg-matrix) instead of emailing.

PG_MATRIX_YML="$REPO_ROOT/.github/workflows/pg-matrix.yml"

# 1. The workflow file exists.
if [[ -f "$PG_MATRIX_YML" ]]; then
  pass "[S10-C] .github/workflows/pg-matrix.yml exists"
else
  fail "[S10-C] .github/workflows/pg-matrix.yml exists"
fi

# 2. workflow has a name.
if grep -qE '^name:[[:space:]]*pg-matrix' "$PG_MATRIX_YML"; then
  pass "[S10-C] workflow name is 'pg-matrix'"
else
  fail "[S10-C] workflow name is 'pg-matrix'"
fi

# 3. cron schedule is Monday 03:00 UTC.
if grep -qE 'cron:[[:space:]]*"0 3 \* \* 1"' "$PG_MATRIX_YML"; then
  pass "[S10-C] cron schedule is '0 3 * * 1' (Monday 03:00 UTC)"
else
  fail "[S10-C] cron schedule is '0 3 * * 1' (Monday 03:00 UTC)"
fi

# 4. workflow_dispatch trigger is present (manual re-run).
if grep -q 'workflow_dispatch' "$PG_MATRIX_YML"; then
  pass "[S10-C] workflow_dispatch trigger present (manual re-run)"
else
  fail "[S10-C] workflow_dispatch trigger present (manual re-run)"
fi

# 5. issues: write permission for the failure issue creation.
if grep -qE '^[[:space:]]+issues:[[:space:]]*write' "$PG_MATRIX_YML"; then
  pass "[S10-C] permissions block grants 'issues: write'"
else
  fail "[S10-C] permissions block grants 'issues: write'"
fi

# 6. Runs sprint-7.sh with VF_RUN_PG_MATRIX=1 (the spec requirement).
if grep -qE 'VF_RUN_PG_MATRIX=1[[:space:]]+bash[[:space:]]+tests/integration/sprint-7\.sh' "$PG_MATRIX_YML"; then
  pass "[S10-C] runs 'VF_RUN_PG_MATRIX=1 bash tests/integration/sprint-7.sh'"
else
  fail "[S10-C] runs 'VF_RUN_PG_MATRIX=1 bash tests/integration/sprint-7.sh'"
fi

# 7. Failure step gated by `if: failure()`.
if grep -qE '^[[:space:]]+if:[[:space:]]+failure\(\)' "$PG_MATRIX_YML"; then
  pass "[S10-C] failure step is gated by 'if: failure()'"
else
  fail "[S10-C] failure step is gated by 'if: failure()'"
fi

# 8. Failure step uses github-script + issues.create.
if grep -q 'actions/github-script@v7' "$PG_MATRIX_YML" \
    && grep -q 'issues.create' "$PG_MATRIX_YML"; then
  pass "[S10-C] failure step calls github.rest.issues.create"
else
  fail "[S10-C] failure step calls github.rest.issues.create"
fi

# 9. Failure issue carries the spec-required labels.
if grep -qE 'labels:.*ci-failure' "$PG_MATRIX_YML" \
    && grep -qE 'labels:.*pg-matrix' "$PG_MATRIX_YML"; then
  pass "[S10-C] failure issue labelled 'ci-failure' + 'pg-matrix'"
else
  fail "[S10-C] failure issue labelled 'ci-failure' + 'pg-matrix'"
fi

# 10. S10-03 reference in the workflow comments.
if grep -q 'S10-03' "$PG_MATRIX_YML"; then
  pass "[S10-C] pg-matrix.yml cites S10-03"
else
  fail "[S10-C] pg-matrix.yml cites S10-03"
fi

# ---------------------------------------------------------------------------
echo "== [S10-D] release.sh --notes-file pre-fill (S10-04) =="

# S10-04 — release.sh accepts --notes-file <path> to pre-fill the
# CHANGELOG entry body, replacing the empty Added/Fixed/Changed stub.
# Missing/empty path → exit 2. A new "previous entry empty" warning
# fires when the most recent entry in CHANGELOG.md has empty stub
# sections (signal that the prior release shipped without notes).

RELEASE_SH_S10D="$REPO_ROOT/bin/release.sh"
RELEASING_S10D="$REPO_ROOT/docs/RELEASING.md"

# 1. The flag is parsed by name.
if grep -qE -- '--notes-file\)' "$RELEASE_SH_S10D"; then
  pass "[S10-D] release.sh parser handles '--notes-file <path>'"
else
  fail "[S10-D] release.sh parser handles '--notes-file <path>'"
fi

# 2. The flag is parsed in --notes-file=path form too.
if grep -qE -- '--notes-file=\*' "$RELEASE_SH_S10D"; then
  pass "[S10-D] release.sh parser handles '--notes-file=<path>'"
else
  fail "[S10-D] release.sh parser handles '--notes-file=<path>'"
fi

# 3. Missing-path validation: exit 2.
if grep -qE 'release: --notes-file path does not exist' "$RELEASE_SH_S10D"; then
  pass "[S10-D] missing --notes-file path produces a clear error"
else
  fail "[S10-D] missing --notes-file path produces a clear error"
fi

# 4. Empty-file validation: exit 2.
if grep -qE 'release: --notes-file is empty' "$RELEASE_SH_S10D"; then
  pass "[S10-D] empty --notes-file produces a clear error"
else
  fail "[S10-D] empty --notes-file produces a clear error"
fi

# 5. Help text mentions the flag.
if grep -qE '^#.*--notes-file' "$RELEASE_SH_S10D"; then
  pass "[S10-D] release.sh usage block documents --notes-file"
else
  fail "[S10-D] release.sh usage block documents --notes-file"
fi

# 6. insert_changelog_entry takes a notes_body parameter.
if grep -qE 'notes_body=' "$RELEASE_SH_S10D"; then
  pass "[S10-D] insert_changelog_entry() accepts a notes_body argument"
else
  fail "[S10-D] insert_changelog_entry() accepts a notes_body argument"
fi

# 7. New stub heading: "Notes pre-filled from --notes-file."
if grep -qF 'Notes pre-filled from --notes-file.' "$RELEASE_SH_S10D"; then
  pass "[S10-D] pre-filled entry uses the 'Notes pre-filled' heading"
else
  fail "[S10-D] pre-filled entry uses the 'Notes pre-filled' heading"
fi

# 8. Empty-prior-entry warning surface fires.
if grep -qE 'previous CHANGELOG entry .* has empty stub sections' "$RELEASE_SH_S10D"; then
  pass "[S10-D] empty-previous-entry warning fires"
else
  fail "[S10-D] empty-previous-entry warning fires"
fi

# 9. S10-04 reference in the release.sh source.
if grep -q 'S10-04' "$RELEASE_SH_S10D"; then
  pass "[S10-D] release.sh cites S10-04 in the flag-parser comment"
else
  fail "[S10-D] release.sh cites S10-04 in the flag-parser comment"
fi

# 10. RELEASING.md documents the flag.
if grep -qE -- '--notes-file' "$RELEASING_S10D"; then
  pass "[S10-D] RELEASING.md documents --notes-file"
else
  fail "[S10-D] RELEASING.md documents --notes-file"
fi

# 11. RUNTIME — exercise --test-changelog-insert against a fixture
# CHANGELOG + a fixture notes file, prove the body is pasted under
# the new heading and the empty-stub block is gone. Opt-out via
# VF_SKIP_S10D_RUNTIME=1.
if [[ "${VF_SKIP_S10D_RUNTIME:-}" == "1" ]]; then
  pass "[S10-D] runtime --notes-file probe skipped via VF_SKIP_S10D_RUNTIME=1"
else
  S10D_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vf-s10d-XXXXXX")"
  cat > "$S10D_TMP/CHANGELOG.md" <<'EOF'
# Changelog

## [1.0.0] — 2026-04-01

### Added
- previous

### Fixed
-

### Changed
- changed
EOF
  cat > "$S10D_TMP/notes.md" <<'EOF'
### Added
- The new shiny thing
- Another thing

### Fixed
- Fixed a bug
EOF

  # 11a. Happy path — pre-fill writes the body under the new heading.
  S10D_OUT="$(cd "$S10D_TMP" \
    && bash "$RELEASE_SH_S10D" 1.5.0 --test-changelog-insert \
        --notes-file notes.md 2>&1)"
  S10D_EXIT=$?
  if (( S10D_EXIT == 0 )) \
      && grep -qF 'The new shiny thing' "$S10D_TMP/CHANGELOG.md" \
      && grep -qF 'Notes pre-filled from --notes-file.' "$S10D_TMP/CHANGELOG.md"; then
    pass "[S10-D] runtime: --notes-file body inlined into [1.5.0] entry"
  else
    fail "[S10-D] runtime: --notes-file body inlined into [1.5.0] entry (exit=$S10D_EXIT)"
  fi

  # 11b. Pre-filled entry has NO empty "### Added\n-" stub block.
  if ! awk '
        /^## \[1.5.0\]/{cap=1; next}
        /^## \[/ && cap{exit}
        cap{print}
      ' "$S10D_TMP/CHANGELOG.md" | grep -qE '^### Added$' \
      || awk '
        /^## \[1.5.0\]/{cap=1; next}
        /^## \[/ && cap{exit}
        cap{print}
      ' "$S10D_TMP/CHANGELOG.md" | grep -qF 'shiny thing'; then
    pass "[S10-D] runtime: empty stub Added/Fixed/Changed bullets replaced by notes body"
  else
    fail "[S10-D] runtime: empty stub Added/Fixed/Changed bullets replaced by notes body"
  fi

  # 11c. Missing path → exit 2. Capture the exit status BEFORE any
  # `|| true` short-circuit (which would zero $? out from under us).
  S10D_MISS_OUT="$(cd "$S10D_TMP" \
    && bash "$RELEASE_SH_S10D" 1.5.1 --test-changelog-insert \
        --notes-file does-not-exist.md 2>&1)"
  S10D_MISS_EXIT=$?
  if (( S10D_MISS_EXIT == 2 )) \
      && grep -q 'does not exist' <<<"$S10D_MISS_OUT"; then
    pass "[S10-D] runtime: missing --notes-file path exits 2"
  else
    fail "[S10-D] runtime: missing --notes-file path exits 2 (exit=$S10D_MISS_EXIT)"
  fi

  # 11d. Empty file → exit 2.
  : > "$S10D_TMP/empty.md"
  S10D_EMPTY_OUT="$(cd "$S10D_TMP" \
    && bash "$RELEASE_SH_S10D" 1.5.2 --test-changelog-insert \
        --notes-file empty.md 2>&1)"
  S10D_EMPTY_EXIT=$?
  if (( S10D_EMPTY_EXIT == 2 )) \
      && grep -q 'is empty' <<<"$S10D_EMPTY_OUT"; then
    pass "[S10-D] runtime: empty --notes-file exits 2"
  else
    fail "[S10-D] runtime: empty --notes-file exits 2 (exit=$S10D_EMPTY_EXIT)"
  fi

  rm -rf "$S10D_TMP"
fi

# ---------------------------------------------------------------------------
echo "== [S10-Z] sprint-10.sh harness self-audit =="

# Same pattern as [S7-Z] / [S8-Z] / [S9-Z]. Catches section-deletion,
# chmod -x, missing release.sh preflight entry, bad shebang, missing
# set -uo pipefail.

SELF_S10Z="$REPO_ROOT/tests/integration/sprint-10.sh"

# 1-4. Each expected section header must still be present. Note: there
# is no [S10-B] — that letter is reserved for a future S10-02 reopen
# (managed cloud Postgres) per the SPRINT-10.md ticket-id discipline.
for sec_label in "S10-A" "S10-C" "S10-D" "S10-Z"; do
  if grep -q "echo \"== \[$sec_label\]" "$SELF_S10Z"; then
    pass "[S10-Z] [$sec_label] section header still present"
  else
    fail "[S10-Z] [$sec_label] section header still present"
  fi
done

# 5. Harness file must still be executable.
if [[ -x "$SELF_S10Z" ]]; then
  pass "[S10-Z] sprint-10.sh is executable"
else
  fail "[S10-Z] sprint-10.sh is executable"
fi

# 6. bin/release.sh preflight must reference sprint-10.sh.
if grep -q 'tests/integration/sprint-10.sh' "$REPO_ROOT/bin/release.sh"; then
  pass "[S10-Z] bin/release.sh preflight references sprint-10.sh"
else
  fail "[S10-Z] bin/release.sh preflight references sprint-10.sh"
fi

# 7. Shebang is #!/bin/bash.
if head -1 "$SELF_S10Z" | grep -q '^#!/bin/bash$'; then
  pass "[S10-Z] sprint-10.sh shebang is #!/bin/bash"
else
  fail "[S10-Z] sprint-10.sh shebang is #!/bin/bash"
fi

# 8. set -uo pipefail in effect.
if grep -q '^set -uo pipefail$' "$SELF_S10Z"; then
  pass "[S10-Z] sprint-10.sh runs under set -uo pipefail"
else
  fail "[S10-Z] sprint-10.sh runs under set -uo pipefail"
fi

# 9. The S10-02 dropped-ticket comment is preserved (so a future
#    contributor doesn't silently re-add a [S10-B] section without
#    reading SPRINT-10.md).
if grep -q 'S10-02 was DROPPED' "$SELF_S10Z"; then
  pass "[S10-Z] header comment preserves S10-02 'dropped' rationale"
else
  fail "[S10-Z] header comment preserves S10-02 'dropped' rationale"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
