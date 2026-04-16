#!/bin/bash
# VibeFlow Sprint 8 integration harness.
#
# Complements run.sh + sprint-2.sh through sprint-7.sh. Sprint 8
# targets v1.3.0 and picks up items deferred from Sprint 7 + the
# two lessons captured during the v1.2.0 release (Sprint 7 / S7-07).
#
# Sections:
#   [S8-A] — sprint-7.sh [S7-C] multi-tarball save/restore fix (S8-02)
#   [S8-Z] — Sprint 8 harness self-audit (mirrors [S6-Z] / [S7-Z])
#
# Sprint 8 ticket coverage (as of current commit):
#   S8-02 (save/restore fix) → [S8-A]
# S8-01 / S8-03 / S8-04 / S8-05 / S8-06 / S8-07 / S8-08 are not
# yet picked up — if and when they land, they will add their own
# [S8-B/C/…] sections here.
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
echo "== [S8-Z] sprint-8.sh harness self-audit =="

# Same pattern as [S6-Z] / [S7-Z]. Catches section-deletion,
# chmod -x, missing release.sh preflight entry, bad shebang, and
# missing set -uo pipefail — regressions that would silently make
# the gauntlet weaker.

SELF_S8Z="$REPO_ROOT/tests/integration/sprint-8.sh"

# 1-2. Each expected section header must still be present.
for sec_label in "S8-A" "S8-Z"; do
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
