#!/bin/bash
# Sprint 40 integration harness — apply-arbiter-patch archives the artifact to
# .vibeflow/archive/ (a persistent, timestamped version trail) BEFORE editing it,
# distinct from the session rollback snapshot.
#
# Sections:
#   [S40-A] Step 3.5 writes a timestamped archive under .vibeflow/archive/
#   [S40-B] description + Output document the archive
#   [S40-C] runtime: the archive bash produces the right structure
#   [S40-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

APPLY="$REPO_ROOT/skills/apply-arbiter-patch/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S40-A] Step 3.5 archives to .vibeflow/archive/ before editing =="

assert_grep "[S40-A] archives target files under .vibeflow/archive/" \
  '\.vibeflow/archive/' "$APPLY"
assert_grep "[S40-A] archive copy is timestamped (.bak with a UTC timestamp)" \
  'cp -p "\$f" "\.vibeflow/archive/\$f\.\$TS\.bak"' "$APPLY"
assert_grep "[S40-A] timestamp is filesystem-safe (no colons)" \
  'TS="\$\(date -u \+%Y-%m-%dT%H-%M-%SZ\)"' "$APPLY"
assert_grep "[S40-A] archive is BEFORE the first git apply (in Step 3.5)" \
  "before the.*first .git apply.|before the first edit|BEFORE the" "$APPLY"
assert_grep "[S40-A] archive is distinct from the rollback snapshot" \
  "distinct from the session rollback|version trail|version history" "$APPLY"
assert_grep "[S40-A] archive is persistent (never cleaned up)" \
  "never cleaned up|persistent" "$APPLY"
# The rollback snapshot still exists (we ADD the archive, not replace it).
assert_grep "[S40-A] rollback snapshot (arbiter-backups) still present" \
  "arbiter-backups" "$APPLY"

# ---------------------------------------------------------------------------
echo "== [S40-B] description + Output document the archive =="

assert_grep "[S40-B] frontmatter description mentions .vibeflow/archive/" \
  "archives every target file to \.vibeflow/archive/|\.vibeflow/archive/" "$APPLY"
assert_grep "[S40-B] Output lists the archive version trail" \
  '\.vibeflow/archive/<path>\.<timestamp>\.bak' "$APPLY"

# ---------------------------------------------------------------------------
echo "== [S40-C] runtime: archive bash produces the right structure =="

T="$(mktemp -d)"
mkdir -p "$T/docs"
printf '# PRD v1\noriginal content\n' > "$T/docs/PRD.md"
( cd "$T"
  TARGET_FILES=("docs/PRD.md")
  SESSION="probe40"
  SNAP_DIR=".vibeflow/state/arbiter-backups/$SESSION"
  mkdir -p "$SNAP_DIR"
  TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  for f in "${TARGET_FILES[@]}"; do
    [ -f "$f" ] || continue
    mkdir -p "$SNAP_DIR/$(dirname "$f")"
    cp -p "$f" "$SNAP_DIR/$f"
    mkdir -p ".vibeflow/archive/$(dirname "$f")"
    cp -p "$f" ".vibeflow/archive/$f.$TS.bak"
  done
)
# Archive copy exists, timestamped, under .vibeflow/archive/docs/
if ls "$T/.vibeflow/archive/docs/PRD.md."*.bak >/dev/null 2>&1; then
  pass "[S40-C] archive copy written under .vibeflow/archive/docs/ (timestamped .bak)"
else
  fail "[S40-C] archive copy written under .vibeflow/archive/docs/"
fi
# Content matches the pre-edit original.
ARCH="$(ls "$T/.vibeflow/archive/docs/PRD.md."*.bak 2>/dev/null | head -1)"
if [[ -n "$ARCH" ]] && grep -q "original content" "$ARCH"; then
  pass "[S40-C] archived copy preserves the pre-edit content"
else
  fail "[S40-C] archived copy preserves the pre-edit content"
fi
# Rollback snapshot also written (both backups).
if [[ -f "$T/.vibeflow/state/arbiter-backups/probe40/docs/PRD.md" ]]; then
  pass "[S40-C] rollback snapshot also written (archive does not replace it)"
else
  fail "[S40-C] rollback snapshot also written"
fi
rm -rf "$T"

# ---------------------------------------------------------------------------
echo "== [S40-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-40.sh"
assert_grep "[S40-Z] sprint-40.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S40-Z] covers [S40-A]" '\[S40-A\]' "$SELF"
assert_grep "[S40-Z] covers [S40-B]" '\[S40-B\]' "$SELF"
assert_grep "[S40-Z] covers [S40-C]" '\[S40-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
