#!/bin/bash
# Sprint 22 integration harness — close the action gap: actionable
# learning loop (learning-apply skill).
#
# Sections:
#   [S22-A] learning-apply skill — classify + propose (diff-first)
#   [S22-B] apply confirm + schema re-validation + bounds
#   [S22-C] template-route → phase-specialist bridge
#   [S22-D] LearningApplyConfigSchema + phase-policy
#   [S22-E] Docs (ACTION-GAP.md + LEARNING-APPLY.md + refreshes)
#   [S22-Z] Harness self-audit

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

LA="$REPO_ROOT/skills/learning-apply/SKILL.md"
LANES="$REPO_ROOT/skills/learning-apply/references/lanes.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
SPP="$REPO_ROOT/skills/phase-policy.json"

# ---------------------------------------------------------------------------
echo "== [S22-A] learning-apply skill — classify + propose =="

assert_file "[S22-A] skills/learning-apply/SKILL.md exists" "$LA"
assert_grep "[S22-A] frontmatter has name: learning-apply" "^name: learning-apply" "$LA"
assert_grep "[S22-A] reads consensus-learning-report.md" "consensus-learning-report\\.md" "$LA"
assert_grep "[S22-A] three lanes: config-tune" "config-tune" "$LA"
assert_grep "[S22-A] three lanes: template-route" "template-route" "$LA"
assert_grep "[S22-A] three lanes: escalate" "escalate" "$LA"
assert_grep "[S22-A] diff-first patch under state/patches/learning-" "patches/learning-" "$LA"
assert_grep "[S22-A] writes a manifest.json" "manifest\\.json" "$LA"
assert_grep "[S22-A] audit report learning-apply-decisions.md" "learning-apply-decisions\\.md" "$LA"
assert_grep "[S22-A] NEVER writes config/source directly" "[Nn]ever [Ww]rite|never writes|propose-only|Propose-only" "$LA"
assert_grep "[S22-A] no-lane-match → escalate (never dropped)" "never silently dropped|never .* dropped|escalate" "$LA"
assert_file "[S22-A] references/lanes.md exists" "$LANES"
assert_grep "[S22-A] lanes doc maps consensus.maxIterations" "consensus\\.maxIterations" "$LANES"
assert_grep "[S22-A] lanes doc gives schema clamp ranges" "\\[1, 20\\]|\\[0, 1\\]|clamp" "$LANES"

# ---------------------------------------------------------------------------
echo "== [S22-B] apply confirm + schema re-validation + bounds =="

assert_grep "[S22-B] --dry-run preview flag" "\\-\\-dry-run" "$LA"
assert_grep "[S22-B] --yes apply flag" "\\-\\-yes" "$LA"
assert_grep "[S22-B] default is preview (apply nothing)" "[Pp]review.*default|default.*preview|apply nothing" "$LA"
assert_grep "[S22-B] schema re-validation gate" "schema re-validation|EngineConfigSchema|re-validation" "$LA"
assert_grep "[S22-B] rejects an invalid patched config" "reject" "$LA"
assert_grep "[S22-B] bounds: maxRelativeStep" "maxRelativeStep" "$LA"
assert_grep "[S22-B] clamps to schema range" "clamp" "$LA"
assert_grep "[S22-B] skips below minObservations" "minObservations" "$LA"
assert_grep "[S22-B] applies via git apply" "git apply" "$LA"

# Runtime: the schema re-validation gate actually accepts/rejects.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s22b-XXXXXX")"
OK_OUT="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.safeParse({project:"p", consensus:{maxIterations:7}}).success));' 2>/dev/null)"
assert_eq "[S22-B] runtime: in-range tune passes re-validation" "true" "$OK_OUT"
BAD_OUT="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.safeParse({project:"p", consensus:{maxIterations:99}}).success));' 2>/dev/null)"
assert_eq "[S22-B] runtime: out-of-range tune rejected" "false" "$BAD_OUT"
ENUM_OUT="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.safeParse({project:"p", consensus:{excerptStrategy:"magic"}}).success));' 2>/dev/null)"
assert_eq "[S22-B] runtime: illegal enum tune rejected" "false" "$ENUM_OUT"
rm -rf "$RT"

# ---------------------------------------------------------------------------
echo "== [S22-C] template-route → phase-specialist bridge =="

assert_grep "[S22-C] recurring-suggestion-theme triggers template-route" "recurring-suggestion-theme|RECURRING-SUGGESTION-THEME" "$LA"
assert_grep "[S22-C] maps REQUIREMENTS → prd-rewriter" "prd-rewriter" "$LA"
assert_grep "[S22-C] maps ARCHITECTURE → adr-author" "adr-author" "$LA"
assert_grep "[S22-C] recommends consensus-specialist dispatch" "consensus-specialist" "$LA"
assert_grep "[S22-C] does NOT auto-fork the specialist" "does NOT fork|not auto-fork|does not auto-fork|not fork" "$LA"
assert_grep "[S22-C] lanes doc carries the phase→specialist table" "test-strategy-refiner|coverage-gap-filler|runbook-editor" "$LANES"

# ---------------------------------------------------------------------------
echo "== [S22-D] config + phase-policy =="

assert_grep "[S22-D] config exports LearningApplyConfigSchema" "export const LearningApplyConfigSchema" "$CFG"
assert_grep "[S22-D] default maxRelativeStep 0.5" "maxRelativeStep.*default\\(0\\.5\\)|maxRelativeStep: 0\\.5" "$CFG"
assert_grep "[S22-D] default minObservations 3" "minObservations.*default\\(3\\)|minObservations: 3" "$CFG"
assert_grep "[S22-D] EngineConfigSchema wires learningApply" "learningApply: LearningApplyConfigSchema" "$CFG"
assert_grep "[S22-D] loadFileConfig merges learningApply" "raw\\.learningApply" "$CFG"
assert_grep "[S22-D] config tests cover LearningApplyConfigSchema" "LearningApplyConfigSchema \\(Sprint 22-D\\)" "$CFG_TEST"
if jq -e '.skills["learning-apply"] != null' "$SPP" >/dev/null 2>&1; then
  pass "[S22-D] phase-policy registers learning-apply"
else
  fail "[S22-D] phase-policy registers learning-apply"
fi
if jq -e '.skills["learning-apply"].description | test("propose-only|diff-first")' "$SPP" >/dev/null 2>&1; then
  pass "[S22-D] phase-policy learning-apply notes propose-only/diff-first"
else
  fail "[S22-D] phase-policy learning-apply notes propose-only/diff-first"
fi

# ---------------------------------------------------------------------------
echo "== [S22-E] docs =="

assert_file "[S22-E] docs/ACTION-GAP.md exists" "$REPO_ROOT/docs/ACTION-GAP.md"
assert_file "[S22-E] docs/LEARNING-APPLY.md exists" "$REPO_ROOT/docs/LEARNING-APPLY.md"
assert_grep "[S22-E] ACTION-GAP doc shows observe→frame→act" "observe|frame|act" "$REPO_ROOT/docs/ACTION-GAP.md"
assert_grep "[S22-E] ACTION-GAP doc explains why propose-only" "propose-only|Why propose-only|gate-suppression" "$REPO_ROOT/docs/ACTION-GAP.md"
assert_grep "[S22-E] LEARNING-APPLY doc documents the three lanes" "config-tune|template-route|escalate" "$REPO_ROOT/docs/LEARNING-APPLY.md"
assert_grep "[S22-E] LEARNING-APPLY doc documents safety gates" "schema re-validation|Bounded|Propose-only" "$REPO_ROOT/docs/LEARNING-APPLY.md"
assert_grep "[S22-E] LEARNING-LOOP doc links the apply step" "learning-apply|LEARNING-APPLY|action gap" "$REPO_ROOT/docs/LEARNING-LOOP.md"
assert_grep "[S22-E] CONSENSUS-FLOW references the action gap" "action gap|learning-apply|ACTION-GAP" "$REPO_ROOT/docs/CONSENSUS-FLOW.md"

# ---------------------------------------------------------------------------
echo "== [S22-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-22.sh"
if [[ -x "$SELF" ]]; then pass "[S22-Z] sprint-22.sh is executable"; else fail "[S22-Z] sprint-22.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S22-Z] sprint-22.sh shebang is #!/bin/bash"
else fail "[S22-Z] sprint-22.sh shebang is #!/bin/bash"; fi
for sec in S22-A S22-B S22-C S22-D S22-E S22-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S22-Z] [$sec] section header present"
  else fail "[S22-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
