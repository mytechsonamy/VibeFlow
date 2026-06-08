#!/bin/bash
# Sprint 41 integration harness — DEVELOPMENT/DEPLOYMENT analyzers run as skills,
# and phase-runner resolves the DEVELOPMENT diff robustly (no exit-128 on
# single-commit / non-git, reviews the whole increment).
#
# Sections:
#   [S41-A] the 3 auto-satisfy analyzers are model-invocable (phase-runner can run them)
#   [S41-B] phase-runner resolves the DEVELOPMENT diff robustly
#   [S41-C] runtime — the base resolver handles single-commit + multi-commit
#   [S41-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S41-A] auto-satisfy analyzers are model-invocable =="

for s in quality-gates release-decision-engine deploy-verifier; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  if ! grep -q '^disable-model-invocation: true$' "$f" 2>/dev/null; then
    pass "[S41-A] $s is model-invocable (phase-runner can run it)"
  else
    fail "[S41-A] $s is model-invocable ($s still disable-model-invocation:true)"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S41-B] phase-runner resolves the DEVELOPMENT diff robustly =="

assert_grep "[S41-B] guards that it's a git repo" \
  "git rev-parse --is-inside-work-tree" "$RUNNER"
assert_grep "[S41-B] prefers the increment base via merge-base with the default branch" \
  "git merge-base HEAD" "$RUNNER"
assert_grep "[S41-B] falls back to HEAD~1 when no base" \
  "rev-parse HEAD~1|HEAD~1" "$RUNNER"
assert_grep "[S41-B] single-commit fallback uses the empty tree (first commit reviewable)" \
  "hash-object -t tree /dev/null|empty tree" "$RUNNER"
assert_grep "[S41-B] notes the literal HEAD~1..HEAD fails 128 on <2 commits" \
  "exit 128|fewer than two commits|fails with exit 128" "$RUNNER"
assert_grep "[S41-B] analyzer-map no longer hardcodes HEAD~1..HEAD as the only primary" \
  "not.*hardcoded .HEAD~1\.\.HEAD|base resolved robustly" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S41-C] runtime — base resolver handles single + multi commit =="

# Replicate the resolver (subset: no remote default branch in the probe).
resolve_range() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "NO-GIT"; return; }
  local BASE
  BASE="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo '')"
  if [ -z "$BASE" ]; then
    if git rev-parse HEAD~1 >/dev/null 2>&1; then BASE="HEAD~1"
    else BASE="$(git hash-object -t tree /dev/null)"; fi
  fi
  echo "$BASE..HEAD"
}

# single-commit repo → must NOT be HEAD~1 (would 128); must diff cleanly
T="$(mktemp -d)"; ( cd "$T" && git init -q && git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m one )
R1="$( cd "$T" && resolve_range )"
if [[ "$R1" != "HEAD~1..HEAD" && "$R1" == *..HEAD ]] && ( cd "$T" && git diff "$R1" >/dev/null 2>&1 ); then
  pass "[S41-C] single-commit repo → empty-tree base, git diff succeeds (no exit 128)"
else
  fail "[S41-C] single-commit repo → clean diff (got range '$R1')"
fi
rm -rf "$T"

# two-commit repo → HEAD~1..HEAD, diff succeeds
T="$(mktemp -d)"; ( cd "$T" && git init -q \
  && printf 'a\n' > f && git add f && git -c user.email=a@b.c -c user.name=t commit -q -m one \
  && printf 'b\n' >> f && git add f && git -c user.email=a@b.c -c user.name=t commit -q -m two )
R2="$( cd "$T" && resolve_range )"
if ( cd "$T" && git diff "$R2" >/dev/null 2>&1 ) && [[ "$R2" == *..HEAD ]]; then
  pass "[S41-C] two-commit repo → valid range '$R2', git diff succeeds"
else
  fail "[S41-C] two-commit repo → valid diff range (got '$R2')"
fi
rm -rf "$T"

# non-git dir → NO-GIT (graceful, not a crash)
T="$(mktemp -d)"
R3="$( cd "$T" && resolve_range )"
[[ "$R3" == "NO-GIT" ]] && pass "[S41-C] non-git dir → graceful NO-GIT (no crash)" \
  || fail "[S41-C] non-git dir → graceful NO-GIT (got '$R3')"
rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S41-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-41.sh"
assert_grep "[S41-Z] sprint-41.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S41-Z] covers [S41-A]" '\[S41-A\]' "$SELF"
assert_grep "[S41-Z] covers [S41-B]" '\[S41-B\]' "$SELF"
assert_grep "[S41-Z] covers [S41-C]" '\[S41-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
