#!/bin/bash
# Sprint 27 integration harness — template-route autonomy:
# propose-only specialist auto-fork.
#
# Sections:
#   [S27-A] autoForkSpecialist config opt-in
#   [S27-B] learning-apply auto-fork lane (propose-only)
#   [S27-C] phase specialists accept a learning-fork brief
#   [S27-D] Docs (TEMPLATE-AUTONOMY.md + refreshes)
#   [S27-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
LA="$REPO_ROOT/skills/learning-apply/SKILL.md"
LANES="$REPO_ROOT/skills/learning-apply/references/lanes.md"
BRIEF="$REPO_ROOT/agents/_shared/learning-fork-brief.md"

# ---------------------------------------------------------------------------
echo "== [S27-A] autoForkSpecialist config opt-in =="

assert_grep "[S27-A] config adds autoForkSpecialist (default false)" \
  "autoForkSpecialist: z.boolean\\(\\).default\\(false\\)" "$CFG"
assert_grep "[S27-A] nested in LearningApplyConfigSchema default literal" \
  "autoForkSpecialist: false" "$CFG"
assert_grep "[S27-A] config tests cover autoForkSpecialist" \
  "autoForkSpecialist" "$CFG_TEST"
DEF="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.parse({project:"p"}).learningApply.autoForkSpecialist));' 2>/dev/null)"
assert_eq "[S27-A] runtime: autoForkSpecialist defaults to false" "false" "$DEF"
ON="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.parse({project:"p",learningApply:{autoForkSpecialist:true}}).learningApply.autoForkSpecialist));' 2>/dev/null)"
assert_eq "[S27-A] runtime: accepts autoForkSpecialist:true" "true" "$ON"

# ---------------------------------------------------------------------------
echo "== [S27-B] learning-apply auto-fork lane (propose-only) =="

assert_grep "[S27-B] reads autoForkSpecialist" "autoForkSpecialist" "$LA"
assert_grep "[S27-B] default-off keeps recommend-only" "recommend-only|recommend\\b.*only|dispatch recommendation" "$LA"
assert_grep "[S27-B] on → writes a learning-fork brief" "learning-fork brief|learning-fork-|brief\\.md" "$LA"
assert_grep "[S27-B] on → forks the matching phase specialist" "fork the matching phase specialist|auto-fork" "$LA"
assert_grep "[S27-B] patch under .vibeflow/state/patches/learning-fork-" "patches/learning-fork-" "$LA"
assert_grep "[S27-B] NEVER applies the patch (propose-only)" "NEVER applies|never applies|propose-only" "$LA"
assert_grep "[S27-B] operator confirms via apply-arbiter-patch" "apply-arbiter-patch" "$LA"
assert_grep "[S27-B] honours minObservations + enabled" "minObservations|learningApply\\.enabled" "$LA"
assert_grep "[S27-B] lanes doc documents the auto-fork option" "autoForkSpecialist" "$LANES"
assert_grep "[S27-B] lanes doc keeps propose-only" "[Pp]ropose-only|never applies" "$LANES"

# ---------------------------------------------------------------------------
echo "== [S27-C] phase specialists accept a learning-fork brief =="

assert_file "[S27-C] agents/_shared/learning-fork-brief.md exists" "$BRIEF"
assert_grep "[S27-C] brief documents the format" "theme:|primaryArtifact:|seenCount:" "$BRIEF"
assert_grep "[S27-C] brief keeps diff-first / never-write-source" "diff-first|never writing|Never write" "$BRIEF"
assert_grep "[S27-C] brief keeps the operator apply path" "apply-arbiter-patch|propose-only" "$BRIEF"
for ag in prd-rewriter design-spec-refiner adr-author test-strategy-refiner coverage-gap-filler runbook-editor; do
  assert_grep "[S27-C] $ag references the learning-fork trigger" \
    "learning-fork|Sprint 27" "$REPO_ROOT/agents/$ag.md"
  assert_grep "[S27-C] $ag still never-writes-source" \
    "never writing the artifact directly|never write|diff-first" "$REPO_ROOT/agents/$ag.md"
done

# ---------------------------------------------------------------------------
echo "== [S27-D] docs =="

assert_file "[S27-D] docs/TEMPLATE-AUTONOMY.md exists" "$REPO_ROOT/docs/TEMPLATE-AUTONOMY.md"
assert_grep "[S27-D] doc explains propose-only template autonomy" "[Pp]ropose-only|confirm-only" "$REPO_ROOT/docs/TEMPLATE-AUTONOMY.md"
assert_grep "[S27-D] doc documents autoForkSpecialist opt-in" "autoForkSpecialist" "$REPO_ROOT/docs/TEMPLATE-AUTONOMY.md"
assert_grep "[S27-D] doc explains why templates stay confirm-only" "not mechanically revertible|stays human-confirmed|stricter" "$REPO_ROOT/docs/TEMPLATE-AUTONOMY.md"
assert_grep "[S27-D] ACTION-GAP references the auto-fork" "auto-fork|TEMPLATE-AUTONOMY|autoForkSpecialist" "$REPO_ROOT/docs/ACTION-GAP.md"
assert_grep "[S27-D] LEARNING-APPLY references the auto-fork" "auto-fork|TEMPLATE-AUTONOMY|autoForkSpecialist" "$REPO_ROOT/docs/LEARNING-APPLY.md"

# ---------------------------------------------------------------------------
echo "== [S27-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-27.sh"
if [[ -x "$SELF" ]]; then pass "[S27-Z] sprint-27.sh is executable"; else fail "[S27-Z] sprint-27.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S27-Z] sprint-27.sh shebang is #!/bin/bash"
else fail "[S27-Z] sprint-27.sh shebang is #!/bin/bash"; fi
for sec in S27-A S27-B S27-C S27-D S27-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S27-Z] [$sec] section header present"
  else fail "[S27-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
