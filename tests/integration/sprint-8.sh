#!/bin/bash
# VibeFlow Sprint 8 integration harness.
#
# Complements run.sh + sprint-2.sh through sprint-7.sh. Sprint 8
# targets v1.3.0 and picks up items deferred from Sprint 7 + the
# two lessons captured during the v1.2.0 release (Sprint 7 / S7-07).
#
# Sections:
#   [S8-A] — sprint-7.sh [S7-C] multi-tarball save/restore fix (S8-02)
#   [S8-B] — CI release workflow wires sprint-6/7/8 harnesses (S8-03)
#   [S8-Z] — Sprint 8 harness self-audit (mirrors [S6-Z] / [S7-Z])
#
# Sprint 8 ticket coverage (as of current commit):
#   S8-02 (save/restore fix)                  → [S8-A]
#   S8-03 (CI workflow consolidation)         → [S8-B]
# S8-01 / S8-04 / S8-05 / S8-06 / S8-07 / S8-08 are not yet
# picked up — if and when they land, they will add their own
# [S8-C/D/…] sections here.
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
echo "== [S8-A] sprint-7.sh [S7-C] multi-tarball save/restore fix =="

# S8-02 — the [S7-C] determinism runtime sentinel used to save
# only the first pre-existing tarball (`ls | head -1`) but delete
# all of them (`rm -f vibeflow-plugin-*.tar.gz`). When the harness
# ran with multiple version tarballs on disk (e.g. right after a
# fresh `release.sh <newer>` produced a new tarball alongside an
# older one), the new release artifact got clobbered and only the
# older one survived. This bit the v1.2.0 release during S7-07 —
# see the Sprint 7 closure commit body.
#
# The fix: save/restore via `mv vibeflow-plugin-*.tar.gz $SAVED/`
# in a for-loop so EVERY matching file is preserved.
#
# Sentinels:
#   1-4. Source-grep the new save/restore structure in sprint-7.sh
#        ([S7-C] section) so a future refactor can't silently
#        regress it.
#   5.   RUNTIME — seed TWO fixture tarballs (a fake 0.9.9 and
#        the real v1.2.0-or-whatever is on disk), run sprint-7.sh,
#        verify BOTH fixtures are present after and unchanged.

SPRINT7_S8A="$REPO_ROOT/tests/integration/sprint-7.sh"

# 1. The save loop must use `for … in vibeflow-plugin-*.tar.gz`,
#    NOT `ls | head -1`. Grep for both the glob-expansion shape
#    AND the absence of the single-file `head -1` pattern.
if grep -q 'for f in.*vibeflow-plugin-\*\.tar\.gz' "$SPRINT7_S8A"; then
  pass "[S8-A] sprint-7.sh save loop iterates every tarball match"
else
  fail "[S8-A] sprint-7.sh save loop iterates every tarball match"
fi

# 2. Must NOT still have the `ls | head -1` single-tarball save
#    pattern in the [S7-C] block. This was the root cause bug.
# We look for the specific pre-fix idiom only; `head -1` can show
# up legitimately elsewhere in the harness.
if grep -q 'SAVED_TARBALL=.*ls.*head -1' "$SPRINT7_S8A"; then
  fail "[S8-A] sprint-7.sh still uses the old single-tarball save (ls | head -1)"
else
  pass "[S8-A] sprint-7.sh no longer uses the single-tarball save (ls | head -1)"
fi

# 3. The saved dir must be created explicitly (mkdir -p) — the for
#    loop's `mv` depends on the destination existing.
if grep -q 'mkdir -p "\$SAVED_DIR"' "$SPRINT7_S8A"; then
  pass "[S8-A] sprint-7.sh creates the \$SAVED_DIR before moving tarballs"
else
  fail "[S8-A] sprint-7.sh creates the \$SAVED_DIR before moving tarballs"
fi

# 4. Restore must also iterate via the for-loop. Matches the save.
if grep -q 'for f in "\$SAVED_DIR"/vibeflow-plugin' "$SPRINT7_S8A"; then
  pass "[S8-A] sprint-7.sh restore loop iterates every saved tarball"
else
  fail "[S8-A] sprint-7.sh restore loop iterates every saved tarball"
fi

# 5. S8-02 reference in the code comment so a future contributor
#    can trace back to this ticket + the v1.2.0 incident.
if grep -q 'S8-02' "$SPRINT7_S8A"; then
  pass "[S8-A] sprint-7.sh [S7-C] cites S8-02 in the comment"
else
  fail "[S8-A] sprint-7.sh [S7-C] cites S8-02 in the comment"
fi

# 6. RUNTIME — seed two fixture tarballs, run sprint-7.sh, verify
#    both survive with identical sha256 after.
#
# Requires package-plugin.sh to work, which requires pg installed
# (S7-04 step [0.5] would abort otherwise for a real release; the
# [S7-C] determinism check doesn't invoke release.sh but it DOES
# invoke package-plugin.sh directly, which needs build-all.sh's
# prerequisites — but package-plugin.sh has --skip-build so it
# does NOT need pg). Skip the runtime probe gracefully when
# VF_SKIP_S8A_RUNTIME=1 is set.
if [[ "${VF_SKIP_S8A_RUNTIME:-}" == "1" ]]; then
  pass "[S8-A] runtime save/restore probe skipped via VF_SKIP_S8A_RUNTIME=1"
else
  FIXTURE_A="$REPO_ROOT/vibeflow-plugin-0.0.1.tar.gz"
  FIXTURE_A_SHA="$REPO_ROOT/vibeflow-plugin-0.0.1.tar.gz.sha256"
  FIXTURE_B="$REPO_ROOT/vibeflow-plugin-0.0.2.tar.gz"
  FIXTURE_B_SHA="$REPO_ROOT/vibeflow-plugin-0.0.2.tar.gz.sha256"

  # Make two distinct fake tarballs so we can verify each one's
  # bytes survive unchanged. Use `dd` with different block counts
  # so the sha256 differs between them.
  if dd if=/dev/urandom of="$FIXTURE_A" bs=512 count=1 >/dev/null 2>&1 \
      && dd if=/dev/urandom of="$FIXTURE_B" bs=1024 count=1 >/dev/null 2>&1; then
    shasum -a 256 "$FIXTURE_A" > "$FIXTURE_A_SHA"
    shasum -a 256 "$FIXTURE_B" > "$FIXTURE_B_SHA"
    SHA_A_BEFORE="$(shasum -a 256 "$FIXTURE_A" | awk '{print $1}')"
    SHA_B_BEFORE="$(shasum -a 256 "$FIXTURE_B" | awk '{print $1}')"

    # Run sprint-7.sh (which exercises [S7-C]). We pipe stdout/stderr
    # away — we only care about post-run state.
    bash "$SPRINT7_S8A" >/dev/null 2>&1 || true

    # Check both fixtures still exist and sha256 is unchanged.
    if [[ -f "$FIXTURE_A" ]] && [[ -f "$FIXTURE_B" ]]; then
      SHA_A_AFTER="$(shasum -a 256 "$FIXTURE_A" | awk '{print $1}')"
      SHA_B_AFTER="$(shasum -a 256 "$FIXTURE_B" | awk '{print $1}')"
      if [[ "$SHA_A_BEFORE" == "$SHA_A_AFTER" ]] && [[ "$SHA_B_BEFORE" == "$SHA_B_AFTER" ]]; then
        pass "[S8-A] both fixture tarballs survive sprint-7.sh [S7-C] with bytes unchanged"
      else
        fail "[S8-A] fixture sha256 drifted across [S7-C] run"
      fi
    else
      fail "[S8-A] fixture tarballs missing after [S7-C] run — save/restore bug regressed"
    fi

    # Clean up the fixtures.
    rm -f "$FIXTURE_A" "$FIXTURE_A_SHA" "$FIXTURE_B" "$FIXTURE_B_SHA"
  else
    fail "[S8-A] could not create fixture tarballs (dd unavailable?)"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S8-B] CI release workflow wires sprint-6/7/8 harnesses =="

# S8-03 — Sprint 6 / S6-01 wanted to add sprint-6.sh to the CI
# release workflow but the author's PAT lacked `workflow` scope.
# Sprint 7 / S7-06 hit the same blocker for sprint-7.sh. Sprint 8
# consolidates all three deferred workflow updates (sprint-6.sh,
# sprint-7.sh, sprint-8.sh) into one user-gated commit that the
# maintainer pushes with a workflow-scoped token.
#
# These sentinels grep the release workflow YAML for each harness.
# If a future refactor drops one, the sentinel fires immediately
# — catches the regression before the next release tag push.

RELEASE_WORKFLOW_S8B="$REPO_ROOT/.github/workflows/release.yml"

if [[ -f "$RELEASE_WORKFLOW_S8B" ]]; then
  # 1-3. Each Sprint 6/7/8 harness must be named in the gauntlet step.
  for harness_name in "sprint-6.sh" "sprint-7.sh" "sprint-8.sh"; do
    if grep -q "tests/integration/$harness_name" "$RELEASE_WORKFLOW_S8B"; then
      pass "[S8-B] release.yml preflight runs $harness_name"
    else
      fail "[S8-B] release.yml preflight runs $harness_name"
    fi
  done

  # 4. sprint-6.sh needs both VF_SKIP_LIVE_POSTGRES=1 AND
  #    VF_SKIP_NEXT_BUILD=1 because [S6-B]'s optional next-build
  #    gate would otherwise try to `npm install && npm run build`
  #    in the Next.js demo on every CI release — slow and fragile
  #    on a fresh runner.
  if grep -q 'VF_SKIP_LIVE_POSTGRES=1 VF_SKIP_NEXT_BUILD=1' "$RELEASE_WORKFLOW_S8B" \
      || grep -qE 'VF_SKIP_NEXT_BUILD=1.*sprint-6' "$RELEASE_WORKFLOW_S8B" \
      || grep -qE 'sprint-6.*VF_SKIP_NEXT_BUILD' "$RELEASE_WORKFLOW_S8B"; then
    pass "[S8-B] release.yml skips sprint-6.sh's optional next build in CI"
  else
    fail "[S8-B] release.yml skips sprint-6.sh's optional next build in CI"
  fi

  # 5. sprint-5.sh must STILL be wired (we only added three new
  #    harnesses, we didn't replace the existing sprint-5 line).
  if grep -q "VF_SKIP_LIVE_POSTGRES=1 bash tests/integration/sprint-5.sh" "$RELEASE_WORKFLOW_S8B"; then
    pass "[S8-B] release.yml still runs sprint-5.sh with VF_SKIP_LIVE_POSTGRES=1"
  else
    fail "[S8-B] release.yml still runs sprint-5.sh with VF_SKIP_LIVE_POSTGRES=1"
  fi

  # 6. S8-03 reference in the comment block so a future contributor
  #    reading the workflow can trace back to this ticket + the
  #    three sibling tickets whose workflow updates consolidated here.
  if grep -q 'S8-03' "$RELEASE_WORKFLOW_S8B"; then
    pass "[S8-B] release.yml cites S8-03 in the preflight comment block"
  else
    fail "[S8-B] release.yml cites S8-03 in the preflight comment block"
  fi
else
  fail "[S8-B] .github/workflows/release.yml present"
fi

# ---------------------------------------------------------------------------
echo "== [S8-C] prerelease / beta-channel release workflow =="

# S8-01 — bin/release.sh gets a --prerelease mode so maintainers can
# cut 1.3.0-rc.1 / 1.3.0-beta.2 / 1.3.0-alpha.N-style tags without
# the strict SemVer guard aborting them. Prerelease entries sit
# under a dedicated "## Pre-releases" footer in CHANGELOG.md so they
# never become the "latest" stable entry. Deferred from Sprint 6 /
# S6-06 → Sprint 7 / S7-03 → Sprint 8 / S8-01. Spec:
# docs/superpowers/specs/2026-04-16-s8-01-prerelease-workflow-design.md
#
# Sentinels:
#   1-7.  Static — grep release.sh + CHANGELOG.md + RELEASING.md for
#         the required surface (flag parser, regex, two-mode insert,
#         conditional hint, footer header, promotion docs).
#   8-11. Runtime — exercise `release.sh <ver> --dry-run` in all four
#         (mode × version) quadrants to catch behavioural regressions.
#         Opt out via VF_SKIP_S8C_RUNTIME=1.

RELEASE_SH_S8C="$REPO_ROOT/bin/release.sh"
CHANGELOG_S8C="$REPO_ROOT/CHANGELOG.md"
RELEASING_S8C="$REPO_ROOT/docs/RELEASING.md"

# 1. release.sh parses --prerelease flag.
if grep -q '"--prerelease")' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh parses --prerelease flag"
else
  fail "[S8-C] release.sh parses --prerelease flag"
fi

# 2. release.sh defines SemVer prerelease regex.
if grep -qE 'SEMVER_PRERELEASE=.*0-9A-Za-z' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh defines SemVer prerelease regex"
else
  fail "[S8-C] release.sh defines SemVer prerelease regex"
fi

# 3. release.sh rejects prerelease string when --prerelease missing.
if grep -q 'requires --prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh errors on prerelease version without --prerelease"
else
  fail "[S8-C] release.sh errors on prerelease version without --prerelease"
fi

# 4. release.sh rejects --prerelease with strict X.Y.Z.
if grep -q 'only for SemVer prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh errors on --prerelease with stable X.Y.Z"
else
  fail "[S8-C] release.sh errors on --prerelease with stable X.Y.Z"
fi

# 5. CHANGELOG.md contains "## Pre-releases" footer.
if grep -q '^## Pre-releases$' "$CHANGELOG_S8C"; then
  pass "[S8-C] CHANGELOG.md has a ## Pre-releases footer"
else
  fail "[S8-C] CHANGELOG.md has a ## Pre-releases footer"
fi

# 6. release.sh calls insert_changelog_entry with prerelease mode arg.
if grep -qE 'insert_changelog_entry ".*\$PRERELEASE"' "$RELEASE_SH_S8C" \
    || grep -qE 'insert_changelog_entry .*\$PRERELEASE' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh passes PRERELEASE into insert_changelog_entry"
else
  fail "[S8-C] release.sh passes PRERELEASE into insert_changelog_entry"
fi

# 7. release.sh emits --prerelease hint for gh release create.
if grep -q 'gh release create.*--prerelease' "$RELEASE_SH_S8C"; then
  pass "[S8-C] release.sh emits --prerelease hint for gh release create"
else
  fail "[S8-C] release.sh emits --prerelease hint for gh release create"
fi

# 8-11. Runtime — exercise release.sh --dry-run in all four
# (mode × version) quadrants. Needs a clean working tree + pg
# peer dep installed (step [0.5]) just like any release.sh call.
# Skip gracefully via VF_SKIP_S8C_RUNTIME=1 for environments that
# can't satisfy those prereqs.
if [[ "${VF_SKIP_S8C_RUNTIME:-}" == "1" ]]; then
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
  pass "[S8-C] runtime release.sh probes skipped via VF_SKIP_S8C_RUNTIME=1"
else
  # 8. Happy path: --prerelease + prerelease SemVer → exit 0.
  # We must pass a version higher than plugin.json's current; use
  # 9.9.9-rc.1 which will always be greater than anything we've
  # shipped (current: 1.2.0).
  S8C_RUNTIME_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9-rc.1 --prerelease --dry-run 2>&1)"
  S8C_RUNTIME_EXIT=$?
  if (( S8C_RUNTIME_EXIT == 0 )); then
    pass "[S8-C] release.sh 9.9.9-rc.1 --prerelease --dry-run exits 0"
  else
    fail "[S8-C] release.sh 9.9.9-rc.1 --prerelease --dry-run exits 0 (got $S8C_RUNTIME_EXIT)"
  fi

  # 9. Happy path output mentions prerelease mode + --prerelease hint.
  if grep -q 'Pre-releases' <<<"$S8C_RUNTIME_OUT" \
      && grep -q 'gh release create.*--prerelease' <<<"$S8C_RUNTIME_OUT"; then
    pass "[S8-C] dry-run output mentions Pre-releases + --prerelease hint"
  else
    fail "[S8-C] dry-run output mentions Pre-releases + --prerelease hint"
  fi

  # 10. Prerelease version without --prerelease → exit 2 + helpful error.
  S8C_MISSING_FLAG_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9-rc.1 --dry-run 2>&1)"
  S8C_MISSING_FLAG_EXIT=$?
  if (( S8C_MISSING_FLAG_EXIT == 2 )) \
      && grep -q 'requires --prerelease' <<<"$S8C_MISSING_FLAG_OUT"; then
    pass "[S8-C] prerelease version without --prerelease exits 2 with hint"
  else
    fail "[S8-C] prerelease version without --prerelease exits 2 with hint (got $S8C_MISSING_FLAG_EXIT)"
  fi

  # 11. Stable X.Y.Z with --prerelease → exit 2 + helpful error.
  S8C_WRONG_MODE_OUT="$(cd "$REPO_ROOT" && bash bin/release.sh 9.9.9 --prerelease --dry-run 2>&1)"
  S8C_WRONG_MODE_EXIT=$?
  if (( S8C_WRONG_MODE_EXIT == 2 )) \
      && grep -q 'only for SemVer prerelease' <<<"$S8C_WRONG_MODE_OUT"; then
    pass "[S8-C] stable version with --prerelease exits 2 with hint"
  else
    fail "[S8-C] stable version with --prerelease exits 2 with hint (got $S8C_WRONG_MODE_EXIT)"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S8-Z] sprint-8.sh harness self-audit =="

# Same pattern as [S6-Z] / [S7-Z]. Catches section-deletion,
# chmod -x, missing release.sh preflight entry, bad shebang, and
# missing set -uo pipefail — regressions that would silently make
# the gauntlet weaker.

SELF_S8Z="$REPO_ROOT/tests/integration/sprint-8.sh"

# 1-3. Each expected section header must still be present.
for sec_label in "S8-A" "S8-B" "S8-C" "S8-Z"; do
  if grep -q "echo \"== \[$sec_label\]" "$SELF_S8Z"; then
    pass "[S8-Z] [$sec_label] section header still present"
  else
    fail "[S8-Z] [$sec_label] section header still present"
  fi
done

# 3. Harness file must still be executable.
if [[ -x "$SELF_S8Z" ]]; then
  pass "[S8-Z] sprint-8.sh is executable"
else
  fail "[S8-Z] sprint-8.sh is executable"
fi

# 4. bin/release.sh preflight must reference sprint-8.sh.
if grep -q 'tests/integration/sprint-8.sh' "$REPO_ROOT/bin/release.sh"; then
  pass "[S8-Z] bin/release.sh preflight references sprint-8.sh"
else
  fail "[S8-Z] bin/release.sh preflight references sprint-8.sh"
fi

# 5. Shebang is #!/bin/bash.
if head -1 "$SELF_S8Z" | grep -q '^#!/bin/bash$'; then
  pass "[S8-Z] sprint-8.sh shebang is #!/bin/bash"
else
  fail "[S8-Z] sprint-8.sh shebang is #!/bin/bash"
fi

# 6. set -uo pipefail in effect.
if grep -q '^set -uo pipefail$' "$SELF_S8Z"; then
  pass "[S8-Z] sprint-8.sh runs under set -uo pipefail"
else
  fail "[S8-Z] sprint-8.sh runs under set -uo pipefail"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
