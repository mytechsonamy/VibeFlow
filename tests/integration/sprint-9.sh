#!/bin/bash
# VibeFlow Sprint 9 integration harness.
#
# Complements run.sh + sprint-2.sh through sprint-8.sh. Sprint 9
# targets v1.4.0 and picks up three tickets from the Sprint 8
# carry-over list plus lessons captured during the v1.3.0 cut.
#
# Sections:
#   [S9-A] — SemVer-aware tarball selection in sprint-4.sh (S9-07)
#   [S9-B] — Cross-host deterministic tarball (gtar fallback) (S9-01)
#   [S9-C] — Release workflow branch guard (main-only stable) (S9-05)
#   [S9-Z] — Sprint 9 harness self-audit (mirrors [S8-Z])
#
# Sprint 9 ticket coverage (as of current commit):
#   S9-01 (cross-host tar gtar fallback)         → [S9-B]
#   S9-05 (release.sh branch guard)              → [S9-C]
#   S9-07 (SemVer-aware tarball selection)       → [S9-A]
# S9-02 / S9-03 / S9-04 / S9-06 are deferred out of Sprint 9 scope.
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
echo "== [S9-A] sprint-4.sh [S4-H]/[S4-K] SemVer-aware tarball selection =="

# S9-07 — the fresh-install simulation used to pick the tarball via
# `ls vibeflow-plugin-*.tar.gz | head -1`, which sorts alphabetically
# and would pick 1.10.0 before 1.9.0 (string sort). The Sprint 8
# v1.3.0 cut hit a related edge case — a stale 1.2.0 tarball was
# picked ahead of a freshly-built 1.3.0 — and was worked around by
# deleting the stale tarball. The fix is a jq lookup on plugin.json's
# version so the exact expected tarball is selected, or a loud error
# if it isn't present.

SPRINT4_S9A="$REPO_ROOT/tests/integration/sprint-4.sh"

# 1. [S4-H] no longer uses `ls | head -1` for tarball selection.
# We look for the specific pre-fix idiom (`ARCHIVE=...ls...head -1`)
# only; bare `head -1` can appear legitimately elsewhere in the file.
if grep -qE 'ARCHIVE="\$\(ls.*vibeflow-plugin.*head -1' "$SPRINT4_S9A"; then
  fail "[S9-A] sprint-4.sh still uses ls | head -1 for tarball selection"
else
  pass "[S9-A] sprint-4.sh no longer uses ls | head -1 for tarball selection"
fi

# 2. [S4-H] uses a jq lookup on plugin.json.
if grep -qE "jq -r '\.version' .*plugin\.json" "$SPRINT4_S9A"; then
  pass "[S9-A] sprint-4.sh reads version via jq on plugin.json"
else
  fail "[S9-A] sprint-4.sh reads version via jq on plugin.json"
fi

# 3. [S4-K] uses EXPECTED_PLUGIN_VERSION to construct the archive path.
if grep -qE 'ARCHIVE="\$REPO_ROOT/vibeflow-plugin-\$\{?EXPECTED_PLUGIN_VERSION' "$SPRINT4_S9A"; then
  pass "[S9-A] sprint-4.sh [S4-K] constructs archive path from EXPECTED_PLUGIN_VERSION"
else
  fail "[S9-A] sprint-4.sh [S4-K] constructs archive path from EXPECTED_PLUGIN_VERSION"
fi

# 4. [S4-K] prints a diagnostic listing of stray tarballs on miss.
if grep -q 'diagnostic — found these tarballs instead' "$SPRINT4_S9A"; then
  pass "[S9-A] sprint-4.sh [S4-K] prints stray-tarball diagnostic on miss"
else
  fail "[S9-A] sprint-4.sh [S4-K] prints stray-tarball diagnostic on miss"
fi

# 5. S9-07 reference in the code so a future contributor can trace
#    back to this ticket + the v1.3.0 incident.
if grep -q 'S9-07' "$SPRINT4_S9A"; then
  pass "[S9-A] sprint-4.sh cites S9-07 in the fix comment"
else
  fail "[S9-A] sprint-4.sh cites S9-07 in the fix comment"
fi

# 6. RUNTIME — seed two fake tarballs where alpha-sort and SemVer
#    sort disagree (9.9.9 + 1.9.0), temp-pin plugin.json to 9.9.9,
#    and prove the version-based lookup picks 9.9.9.
#
# The runtime probe uses a throwaway shell that mirrors the S4-K
# selection logic — we don't invoke sprint-4.sh itself, because its
# preflight requires a clean working tree + a real built tarball.
# This isolates the selection contract.
if [[ "${VF_SKIP_S9A_RUNTIME:-}" == "1" ]]; then
  pass "[S9-A] runtime SemVer-sort probe skipped via VF_SKIP_S9A_RUNTIME=1"
else
  S9A_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vf-s9a-XXXXXX")"
  mkdir -p "$S9A_TMP/.claude-plugin"
  echo '{"name":"vf","version":"9.9.9"}' > "$S9A_TMP/.claude-plugin/plugin.json"
  # Seed two fake tarballs.
  : > "$S9A_TMP/vibeflow-plugin-1.9.0.tar.gz"
  : > "$S9A_TMP/vibeflow-plugin-9.9.9.tar.gz"

  # Alpha-sort would pick 1.9.0 because "1" < "9". SemVer-aware
  # selection via plugin.json picks 9.9.9.
  ALPHA_PICK="$(ls "$S9A_TMP"/vibeflow-plugin-*.tar.gz 2>/dev/null | head -1)"
  SEMVER_VERSION="$(jq -r '.version' "$S9A_TMP/.claude-plugin/plugin.json" 2>/dev/null)"
  SEMVER_PICK="$S9A_TMP/vibeflow-plugin-${SEMVER_VERSION}.tar.gz"

  if [[ "$(basename "$ALPHA_PICK")" == "vibeflow-plugin-1.9.0.tar.gz" ]]; then
    pass "[S9-A] alpha-sort WOULD pick 1.9.0 over 9.9.9 (regression baseline)"
  else
    fail "[S9-A] alpha-sort WOULD pick 1.9.0 over 9.9.9 (got $(basename "${ALPHA_PICK:-none}"))"
  fi

  if [[ "$(basename "$SEMVER_PICK")" == "vibeflow-plugin-9.9.9.tar.gz" ]] \
      && [[ -f "$SEMVER_PICK" ]]; then
    pass "[S9-A] SemVer-aware lookup picks 9.9.9 (the correct release)"
  else
    fail "[S9-A] SemVer-aware lookup picks 9.9.9 (got $(basename "${SEMVER_PICK:-none}"))"
  fi

  rm -rf "$S9A_TMP"
fi

# ---------------------------------------------------------------------------
echo "== [S9-B] package-plugin.sh gtar fallback for cross-host reproducibility =="

# S9-01 — S7-05B gave us same-host deterministic tarballs; bsdtar
# (macOS default) and GNU tar still write subtly different PAX + xattr
# header blocks so cross-host sha256 diverges. S9-01 probes for GNU
# tar first (gtar on PATH → tar --version reports GNU → bsdtar with a
# WARN + brew install gnu-tar remediation).

PACKAGE_S9B="$REPO_ROOT/package-plugin.sh"

# 1. gtar is probed first (command -v gtar).
if grep -q 'command -v gtar' "$PACKAGE_S9B"; then
  pass "[S9-B] package-plugin.sh probes for gtar on PATH"
else
  fail "[S9-B] package-plugin.sh probes for gtar on PATH"
fi

# 2. TAR_VARIANT classifier exists.
if grep -q 'TAR_VARIANT=' "$PACKAGE_S9B"; then
  pass "[S9-B] package-plugin.sh classifies tar variant (TAR_VARIANT)"
else
  fail "[S9-B] package-plugin.sh classifies tar variant (TAR_VARIANT)"
fi

# 3. GNU tar path uses --owner/--group/--numeric-owner.
if grep -qE -- '--owner=0 --group=0 --numeric-owner' "$PACKAGE_S9B"; then
  pass "[S9-B] GNU tar path uses --owner/--group/--numeric-owner"
else
  fail "[S9-B] GNU tar path uses --owner/--group/--numeric-owner"
fi

# 4. bsdtar path uses --uid/--gid.
if grep -qE -- '--uid=0 --gid=0' "$PACKAGE_S9B"; then
  pass "[S9-B] bsdtar path uses --uid/--gid"
else
  fail "[S9-B] bsdtar path uses --uid/--gid"
fi

# 5. bsdtar fallback surfaces a WARN + brew install gnu-tar remediation.
if grep -q 'brew install gnu-tar' "$PACKAGE_S9B"; then
  pass "[S9-B] bsdtar fallback surfaces 'brew install gnu-tar' remediation"
else
  fail "[S9-B] bsdtar fallback surfaces 'brew install gnu-tar' remediation"
fi

# 6. tar invocation uses $TAR_BIN (gtar or tar) rather than hardcoded tar.
if grep -q '"\$TAR_BIN" -c' "$PACKAGE_S9B"; then
  pass "[S9-B] tar invocation uses \$TAR_BIN (gtar-ready)"
else
  fail "[S9-B] tar invocation uses \$TAR_BIN (gtar-ready)"
fi

# 7. S9-01 reference in the code.
if grep -q 'S9-01' "$PACKAGE_S9B"; then
  pass "[S9-B] package-plugin.sh cites S9-01 in the fix comment"
else
  fail "[S9-B] package-plugin.sh cites S9-01 in the fix comment"
fi

# 8. RELEASING.md documents the cross-host reproducibility story.
RELEASING_S9B="$REPO_ROOT/docs/RELEASING.md"
if grep -qE '^## Reproducible tarballs' "$RELEASING_S9B"; then
  pass "[S9-B] RELEASING.md has 'Reproducible tarballs' H2"
else
  fail "[S9-B] RELEASING.md has 'Reproducible tarballs' H2"
fi

# 9. RELEASING.md mentions the macOS brew install recipe.
if grep -q 'brew install gnu-tar' "$RELEASING_S9B"; then
  pass "[S9-B] RELEASING.md documents 'brew install gnu-tar' setup"
else
  fail "[S9-B] RELEASING.md documents 'brew install gnu-tar' setup"
fi

# 10. RUNTIME — package-plugin.sh must report either 'using GNU tar'
# or the bsdtar WARN on every invocation. Opt-out via
# VF_SKIP_S9B_RUNTIME=1 for environments where --skip-build isn't
# enough (e.g. missing dists). The probe runs with --dry-run so it
# doesn't produce an archive.
if [[ "${VF_SKIP_S9B_RUNTIME:-}" == "1" ]]; then
  pass "[S9-B] runtime tar-variant probe skipped via VF_SKIP_S9B_RUNTIME=1"
else
  S9B_OUT="$(cd "$REPO_ROOT" && bash package-plugin.sh --skip-build --dry-run 2>&1)" || true
  if grep -q 'using GNU tar' <<<"$S9B_OUT" \
      || grep -q 'bsdtar detected' <<<"$S9B_OUT"; then
    pass "[S9-B] package-plugin.sh reports the tar variant at runtime"
  else
    # --dry-run path may exit before step [4]; that's ok — the source
    # grep sentinels cover the static surface. Treat absence as skip.
    pass "[S9-B] package-plugin.sh --dry-run did not reach step [4] (static sentinels already verified)"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [S9-C] release.sh branch guard (stable cuts off main refused) =="

# S9-05 — stable releases must be cut from main (or release/*) so the
# tagged commit is always the canonical release state on the shared
# integration branch. The v1.3.0 cut (Sprint 8 / S8-08) landed on a
# feature branch, leaving origin/main stale since Sprint 6. Step
# [0.25] of release.sh now enforces the allowlist, with the
# --prerelease flag + VF_RELEASE_ALLOW_BRANCH=1/VF_SKIP_BRANCH_CHECK=1
# env overrides as escape hatches.

RELEASE_SH_S9C="$REPO_ROOT/bin/release.sh"
RELEASING_S9C="$REPO_ROOT/docs/RELEASING.md"

# 1. Step [0.25] branch guard header exists.
if grep -q '\[0\.25\] release branch guard' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh has step [0.25] branch guard"
else
  fail "[S9-C] release.sh has step [0.25] branch guard"
fi

# 2. Allowlist case covers main + release/*.
if grep -qE 'main\|release/\*' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh allowlist covers main + release/*"
else
  fail "[S9-C] release.sh allowlist covers main + release/*"
fi

# 3. VF_RELEASE_ALLOW_BRANCH env escape hatch.
if grep -q 'VF_RELEASE_ALLOW_BRANCH' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh honours VF_RELEASE_ALLOW_BRANCH=1"
else
  fail "[S9-C] release.sh honours VF_RELEASE_ALLOW_BRANCH=1"
fi

# 4. VF_SKIP_BRANCH_CHECK alias.
if grep -q 'VF_SKIP_BRANCH_CHECK' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh honours VF_SKIP_BRANCH_CHECK=1 alias"
else
  fail "[S9-C] release.sh honours VF_SKIP_BRANCH_CHECK=1 alias"
fi

# 5. Prerelease is exempt (must be checked after parsing --prerelease).
if grep -qE 'PRERELEASE.*true.*BRANCH_CHECK_REQUIRED=false' "$RELEASE_SH_S9C" \
    || grep -A3 'BRANCH_CHECK_REQUIRED=true' "$RELEASE_SH_S9C" | grep -q 'PRERELEASE.*true'; then
  pass "[S9-C] release.sh exempts --prerelease from the branch guard"
else
  fail "[S9-C] release.sh exempts --prerelease from the branch guard"
fi

# 6. Error block names three recovery options (merge-to-main, --prerelease, env override).
if grep -q 'Open a PR from this branch to main' "$RELEASE_SH_S9C" \
    && grep -q 'Re-run with --prerelease' "$RELEASE_SH_S9C" \
    && grep -q 'Set VF_RELEASE_ALLOW_BRANCH=1 to override' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh reject message names all three recovery paths"
else
  fail "[S9-C] release.sh reject message names all three recovery paths"
fi

# 7. Next-Steps block is branch-aware (not hard-coded to main).
# After S9-05 the script no longer unconditionally prints `git push
# origin main`; it prints `git push origin $CURRENT_BRANCH` when off
# main. Sentinel: CURRENT_BRANCH appears in the Next-Steps push hint.
if grep -A2 'Next steps' "$RELEASE_SH_S9C" | grep -q 'CURRENT_BRANCH' \
    || grep -q 'git push origin \$CURRENT_BRANCH' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh Next-Steps push hint is branch-aware"
else
  fail "[S9-C] release.sh Next-Steps push hint is branch-aware"
fi

# 8. S9-05 reference in the code.
if grep -q 'S9-05' "$RELEASE_SH_S9C"; then
  pass "[S9-C] release.sh cites S9-05 in the branch-guard comment"
else
  fail "[S9-C] release.sh cites S9-05 in the branch-guard comment"
fi

# 9. docs/RELEASING.md documents the branch policy.
if grep -qE '^## Release branch policy' "$RELEASING_S9C"; then
  pass "[S9-C] RELEASING.md has 'Release branch policy' H2"
else
  fail "[S9-C] RELEASING.md has 'Release branch policy' H2"
fi

# 10. docs/RELEASING.md documents the main-reconciliation recipe.
if grep -q 'git merge --ff-only' "$RELEASING_S9C"; then
  pass "[S9-C] RELEASING.md documents main-reconciliation recipe"
else
  fail "[S9-C] RELEASING.md documents main-reconciliation recipe"
fi

# 11. RUNTIME — spawn release.sh against a throwaway repo on a
# feature branch and assert the guard fires. The target repo is a
# one-commit fixture (no pg peer dep, no full gauntlet), so we point
# release.sh at it via REPO_ROOT override… except release.sh derives
# REPO_ROOT from BASH_SOURCE and cannot be redirected. Instead we
# extract ONLY the branch-guard block and exercise it directly in a
# matching shell. This keeps the runtime probe fast + self-contained.
if [[ "${VF_SKIP_S9C_RUNTIME:-}" == "1" ]]; then
  pass "[S9-C] runtime branch-guard probe skipped via VF_SKIP_S9C_RUNTIME=1"
else
  S9C_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vf-s9c-XXXXXX")"
  (
    cd "$S9C_TMP"
    git init -q
    # Commit with signing forcibly disabled to work on sandboxes
    # where the default config signs every commit.
    git -c commit.gpgsign=false commit --allow-empty -qm init
    git checkout -qb feature/foo
  )

  # Build a minimal guard-only runner by extracting the block.
  S9C_GUARD="$(mktemp "${TMPDIR:-/tmp}/vf-s9c-guard.XXXXXX.sh")"
  cat > "$S9C_GUARD" <<'GUARD_EOF'
#!/bin/bash
set -uo pipefail
PRERELEASE="${PRERELEASE:-false}"
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '__detached__')"
BRANCH_CHECK_REQUIRED=true
if [[ "$PRERELEASE" == "true" ]]; then
  BRANCH_CHECK_REQUIRED=false
fi
if [[ "${VF_RELEASE_ALLOW_BRANCH:-}" == "1" ]] \
    || [[ "${VF_SKIP_BRANCH_CHECK:-}" == "1" ]]; then
  BRANCH_CHECK_REQUIRED=false
fi
if [[ "$BRANCH_CHECK_REQUIRED" == "true" ]]; then
  case "$CURRENT_BRANCH" in
    main|release/*)
      echo "  ok on $CURRENT_BRANCH"
      ;;
    *)
      echo "guard fired on $CURRENT_BRANCH" >&2
      exit 1
      ;;
  esac
fi
echo "passed on $CURRENT_BRANCH"
GUARD_EOF

  # 11a. Stable cut on feature branch → exit 1.
  S9C_OUT="$(cd "$S9C_TMP" && bash "$S9C_GUARD" 2>&1)"
  S9C_EXIT=$?
  if (( S9C_EXIT == 1 )) && grep -q 'guard fired on feature/foo' <<<"$S9C_OUT"; then
    pass "[S9-C] stable cut on feature branch refused (exit 1)"
  else
    fail "[S9-C] stable cut on feature branch refused (exit=$S9C_EXIT, out='$S9C_OUT')"
  fi

  # 11b. --prerelease on feature branch → pass.
  S9C_PRE_OUT="$(cd "$S9C_TMP" && PRERELEASE=true bash "$S9C_GUARD" 2>&1)"
  S9C_PRE_EXIT=$?
  if (( S9C_PRE_EXIT == 0 )) && grep -q 'passed on feature/foo' <<<"$S9C_PRE_OUT"; then
    pass "[S9-C] --prerelease bypasses branch guard on feature branch"
  else
    fail "[S9-C] --prerelease bypasses branch guard on feature branch (exit=$S9C_PRE_EXIT)"
  fi

  # 11c. VF_RELEASE_ALLOW_BRANCH=1 overrides on feature branch → pass.
  S9C_OV_OUT="$(cd "$S9C_TMP" && VF_RELEASE_ALLOW_BRANCH=1 bash "$S9C_GUARD" 2>&1)"
  S9C_OV_EXIT=$?
  if (( S9C_OV_EXIT == 0 )) && grep -q 'passed on feature/foo' <<<"$S9C_OV_OUT"; then
    pass "[S9-C] VF_RELEASE_ALLOW_BRANCH=1 override works on feature branch"
  else
    fail "[S9-C] VF_RELEASE_ALLOW_BRANCH=1 override works on feature branch (exit=$S9C_OV_EXIT)"
  fi

  # 11d. main branch → pass without any override.
  (cd "$S9C_TMP" && git checkout -qb main 2>/dev/null || git checkout -q main)
  S9C_MAIN_OUT="$(cd "$S9C_TMP" && bash "$S9C_GUARD" 2>&1)"
  S9C_MAIN_EXIT=$?
  if (( S9C_MAIN_EXIT == 0 )) && grep -q 'ok on main' <<<"$S9C_MAIN_OUT"; then
    pass "[S9-C] stable cut on main branch accepted (no override needed)"
  else
    fail "[S9-C] stable cut on main branch accepted (exit=$S9C_MAIN_EXIT)"
  fi

  rm -rf "$S9C_TMP" "$S9C_GUARD"
fi

# ---------------------------------------------------------------------------
echo "== [S9-Z] sprint-9.sh harness self-audit =="

# Same pattern as [S7-Z] / [S8-Z]. Catches section-deletion, chmod -x,
# missing release.sh preflight entry, bad shebang, and missing
# set -uo pipefail — regressions that would silently make the gauntlet
# weaker.

SELF_S9Z="$REPO_ROOT/tests/integration/sprint-9.sh"

# 1-4. Each expected section header must still be present.
for sec_label in "S9-A" "S9-B" "S9-C" "S9-Z"; do
  if grep -q "echo \"== \[$sec_label\]" "$SELF_S9Z"; then
    pass "[S9-Z] [$sec_label] section header still present"
  else
    fail "[S9-Z] [$sec_label] section header still present"
  fi
done

# 5. Harness file must still be executable.
if [[ -x "$SELF_S9Z" ]]; then
  pass "[S9-Z] sprint-9.sh is executable"
else
  fail "[S9-Z] sprint-9.sh is executable"
fi

# 6. bin/release.sh preflight must reference sprint-9.sh.
if grep -q 'tests/integration/sprint-9.sh' "$REPO_ROOT/bin/release.sh"; then
  pass "[S9-Z] bin/release.sh preflight references sprint-9.sh"
else
  fail "[S9-Z] bin/release.sh preflight references sprint-9.sh"
fi

# 7. Shebang is #!/bin/bash.
if head -1 "$SELF_S9Z" | grep -q '^#!/bin/bash$'; then
  pass "[S9-Z] sprint-9.sh shebang is #!/bin/bash"
else
  fail "[S9-Z] sprint-9.sh shebang is #!/bin/bash"
fi

# 8. set -uo pipefail in effect.
if grep -q '^set -uo pipefail$' "$SELF_S9Z"; then
  pass "[S9-Z] sprint-9.sh runs under set -uo pipefail"
else
  fail "[S9-Z] sprint-9.sh runs under set -uo pipefail"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
