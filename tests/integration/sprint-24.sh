#!/bin/bash
# Sprint 24 integration harness — self-correcting auto-apply:
# meta-learning + transactional revert.
#
# Sections:
#   [S24-A] durable auto-apply outcome telemetry
#   [S24-B] auto-tune-ineffective detector
#   [S24-C] learning-apply self-demote + config
#   [S24-D] multi-key transactional revert + config
#   [S24-E] Docs (META-LEARNING.md + refreshes)
#   [S24-Z] Harness self-audit

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
AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
LLE="$REPO_ROOT/skills/learning-loop-engine/SKILL.md"
PATDET="$REPO_ROOT/skills/learning-loop-engine/references/pattern-detection.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
HOOKT="$REPO_ROOT/hooks/tests/run.sh"

# ---------------------------------------------------------------------------
echo "== [S24-A] durable auto-apply outcome telemetry =="

assert_grep "[S24-A] learning-apply writes type:auto-apply row" "type:\"auto-apply\"|\"auto-apply\"" "$LA"
assert_grep "[S24-A] auto-apply row carries key" "type:\"auto-apply\", key" "$LA"
assert_grep "[S24-A] aggregator writes type:auto-apply-held row" "auto-apply-held" "$AGG"
assert_grep "[S24-A] held row carries key for revert-rate" "type:\"auto-apply-held\", key" "$AGG"
assert_grep "[S24-A] hook tests exercise the held row" "S24-A. HELD branch writes auto-apply-held" "$HOOKT"

# ---------------------------------------------------------------------------
echo "== [S24-B] auto-tune-ineffective detector =="

assert_grep "[S24-B] SKILL lists auto-tune-ineffective detector" "auto-tune-ineffective" "$LLE"
assert_grep "[S24-B] SKILL frames it as meta-learning" "meta-loop|meta-learning|own .* tuning" "$LLE"
assert_grep "[S24-B] catalog has LEARNING-AUTO-TUNE-INEFFECTIVE" "LEARNING-AUTO-TUNE-INEFFECTIVE" "$PATDET"
assert_grep "[S24-B] catalog uses revert-rate signature" "revert rate|reverts / auto-applies|reverts ..3" "$PATDET"
assert_grep "[S24-B] catalog keeps the >=3 observation floor" "minObservations.*: 3|3 auto-apply attempts" "$PATDET"
assert_grep "[S24-B] catalog remediation removes the key from allowlist" "autoApply\\.keys" "$PATDET"
assert_grep "[S24-B] catalog version bumped to 3" "patternCatalogVersion: 3" "$PATDET"
assert_grep "[S24-B] catalog count consensus-history 7" "consensus-history patterns: 7" "$PATDET"

# ---------------------------------------------------------------------------
echo "== [S24-C] learning-apply self-demote + config =="

assert_grep "[S24-C] SKILL counts a key's auto-revert rows" "auto-revert.* and .key|select\\(.type==\"auto-revert\"" "$LA"
assert_grep "[S24-C] SKILL demotes on >= demoteAfterReverts" "demoteAfterReverts|demote" "$LA"
assert_grep "[S24-C] SKILL records Applied: demoted" "Applied: demoted|demoted" "$LA"
assert_grep "[S24-C] SKILL keeps the key allowlisted (proposes instead)" "stays allowlisted|propose-only|proposing instead" "$LA"
assert_grep "[S24-C] config exports demoteAfterReverts default 3" "demoteAfterReverts.*default\\(3\\)|demoteAfterReverts: 3" "$CFG"
assert_grep "[S24-C] config tests cover demoteAfterReverts" "demoteAfterReverts" "$CFG_TEST"

# ---------------------------------------------------------------------------
echo "== [S24-D] multi-key transactional revert + config =="

assert_grep "[S24-D] SKILL arms one watch with keys[]" "keys:\\\$keys|keys\\[\\]|transactional" "$LA"
assert_grep "[S24-D] SKILL takes ONE pre-batch snapshot" "ONE snapshot|one .* snapshot|pre-batch" "$LA"
assert_grep "[S24-D] aggregator reads keys // [key]" "keys // \\[\\.key\\]|\\.keys // \\[\\.key\\]" "$AGG"
assert_grep "[S24-D] aggregator cools down every key in the set" "cooldown-.k|for EVERY key|while IFS= read -r k" "$AGG"
assert_grep "[S24-D] config exports transactional default true" "transactional: z.boolean\\(\\).default\\(true\\)|transactional: true" "$CFG"
assert_grep "[S24-D] hook tests exercise the transactional 2-key revert" "S24-D. transactional revert restores" "$HOOKT"

# Runtime: config defaults for the Sprint 24 autoApply fields.
DEFAULTS="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  const a=EngineConfigSchema.parse({project:"p"}).learningApply.autoApply;
  process.stdout.write(a.demoteAfterReverts+":"+a.transactional);' 2>/dev/null)"
assert_eq "[S24-D] runtime: demoteAfterReverts=3 + transactional=true defaults" "3:true" "$DEFAULTS"

# ---------------------------------------------------------------------------
echo "== [S24-E] docs =="

assert_file "[S24-E] docs/META-LEARNING.md exists" "$REPO_ROOT/docs/META-LEARNING.md"
assert_grep "[S24-E] META-LEARNING shows the meta-loop" "meta-loop|self-correct" "$REPO_ROOT/docs/META-LEARNING.md"
assert_grep "[S24-E] META-LEARNING lists the three outcome rows" "auto-apply-held|auto-revert" "$REPO_ROOT/docs/META-LEARNING.md"
assert_grep "[S24-E] META-LEARNING documents self-demote vs cooldown" "self-demote|demoteAfterReverts" "$REPO_ROOT/docs/META-LEARNING.md"
assert_grep "[S24-E] META-LEARNING documents transactional revert" "transactional|atomic" "$REPO_ROOT/docs/META-LEARNING.md"
assert_grep "[S24-E] AUTO-APPLY links the self-correcting loop" "self-correct|META-LEARNING|demoteAfterReverts" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S24-E] LEARNING-LOOP lists the auto-tune-ineffective detector" "auto-tune-ineffective" "$REPO_ROOT/docs/LEARNING-LOOP.md"

# ---------------------------------------------------------------------------
echo "== [S24-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-24.sh"
if [[ -x "$SELF" ]]; then pass "[S24-Z] sprint-24.sh is executable"; else fail "[S24-Z] sprint-24.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S24-Z] sprint-24.sh shebang is #!/bin/bash"
else fail "[S24-Z] sprint-24.sh shebang is #!/bin/bash"; fi
for sec in S24-A S24-B S24-C S24-D S24-E S24-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S24-Z] [$sec] section header present"
  else fail "[S24-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
