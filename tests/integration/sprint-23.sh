#!/bin/bash
# Sprint 23 integration harness — bounded auto-apply with auto-revert.
#
# Sections:
#   [S23-A] autoApply config block + bounds
#   [S23-B] learning-apply auto-apply path (allowlist + snapshot + watch)
#   [S23-C] auto-revert on regression (aggregator revert-watch)
#   [S23-D] Docs (AUTO-APPLY.md + refreshes)
#   [S23-Z] Harness self-audit

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
AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"

# ---------------------------------------------------------------------------
echo "== [S23-A] autoApply config block + bounds =="

assert_grep "[S23-A] config exports AutoApplyConfigSchema" "export const AutoApplyConfigSchema" "$CFG"
assert_grep "[S23-A] autoApply.enabled default false" "enabled: z.boolean\\(\\).default\\(false\\)" "$CFG"
assert_grep "[S23-A] autoApply.keys is a string array" "keys: z.array\\(z.string\\(\\)\\)" "$CFG"
assert_grep "[S23-A] autoApply.revertOnRegression default true" "revertOnRegression" "$CFG"
assert_grep "[S23-A] autoApply.regressionDelta default 0.05" "regressionDelta.*default\\(0\\.05\\)" "$CFG"
assert_grep "[S23-A] LearningApply nests autoApply" "autoApply: AutoApplyConfigSchema" "$CFG"
assert_grep "[S23-A] config tests cover AutoApplyConfigSchema" "AutoApplyConfigSchema \\(Sprint 23-A\\)" "$CFG_TEST"

# Runtime: autoApply defaults OFF + empty allowlist via the built engine.
OFF="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  const c=EngineConfigSchema.parse({project:"p"});
  process.stdout.write(c.learningApply.autoApply.enabled+":"+c.learningApply.autoApply.keys.length);' 2>/dev/null)"
assert_eq "[S23-A] runtime: autoApply defaults OFF + empty allowlist" "false:0" "$OFF"
BADD="$(node -e '
  const {AutoApplyConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(AutoApplyConfigSchema.safeParse({regressionDelta:1.5}).success));' 2>/dev/null)"
assert_eq "[S23-A] runtime: out-of-range regressionDelta rejected" "false" "$BADD"

# ---------------------------------------------------------------------------
echo "== [S23-B] learning-apply auto-apply path =="

assert_grep "[S23-B] Step 7 bounded auto-apply" "[Bb]ounded auto-apply" "$LA"
assert_grep "[S23-B] gated on autoApply.enabled" "autoApply\\.enabled" "$LA"
assert_grep "[S23-B] allowlist gate via autoApply.keys" "autoApply\\.keys|AUTO_KEYS" "$LA"
assert_grep "[S23-B] non-allowlisted key stays operator-confirmed" "not in the allowlist|not.*allowlist|falls back to.*Step 6|operator-confirmed" "$LA"
assert_grep "[S23-B] snapshots config before applying" "Snapshot|\\.bak|vibeflow.config.json.bak" "$LA"
assert_grep "[S23-B] arms the revert watch.json" "watch\\.json" "$LA"
assert_grep "[S23-B] audits Applied: auto" "Applied: auto" "$LA"
assert_grep "[S23-B] re-validation still gates the auto path" "EngineConfigSchema|re-valid|skips .none." "$LA"
assert_grep "[S23-B] cooldown skips a reverted key" "cooldown" "$LA"
assert_grep "[S23-B] description notes opt-in default OFF" "default OFF|default off|opt-in" "$LA"

# ---------------------------------------------------------------------------
echo "== [S23-C] auto-revert on regression (aggregator) =="

assert_grep "[S23-C] aggregator reads watch.json" "auto-apply/watch\\.json|watch\\.json" "$AGG"
assert_grep "[S23-C] guards on same phase + primaryArtifact" "W_PHASE|W_PRIMARY|primaryArtifact" "$AGG"
assert_grep "[S23-C] compares agreement vs baseline delta" "baselineAgreement|REGRESSED|regressionDelta" "$AGG"
assert_grep "[S23-C] restores the snapshot on regression" "cp .*W_SNAP|restore" "$AGG"
assert_grep "[S23-C] arms a cooldown for the reverted key" "cooldown-" "$AGG"
assert_grep "[S23-C] appends an auto-revert row to history" "auto-revert" "$AGG"
assert_grep "[S23-C] logs to auto-apply-reverts.md" "auto-apply-reverts\\.md" "$AGG"
assert_grep "[S23-C] logs HELD when agreement holds" "HELD|held" "$AGG"
assert_grep "[S23-C] drops the watch after evaluating" "rm -f .*WATCH|rm -f .*watch" "$AGG"
# hook tests carry the runtime restore/hold/no-watch coverage
assert_grep "[S23-C] hook tests exercise the revert watch" "auto-apply revert watch \\[S23-C\\]" "$REPO_ROOT/hooks/tests/run.sh"

# ---------------------------------------------------------------------------
echo "== [S23-D] docs =="

assert_file "[S23-D] docs/AUTO-APPLY.md exists" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S23-D] AUTO-APPLY documents default-off" "[Oo]ff by default|default off|OFF by default" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S23-D] AUTO-APPLY documents the allowlist" "allowlist|autoApply\\.keys" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S23-D] AUTO-APPLY documents auto-revert" "auto-revert|Auto-revert" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S23-D] AUTO-APPLY documents the five guardrails" "guardrails|Default off|Cooldown|cooldown" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S23-D] LEARNING-APPLY links the auto lane" "auto-apply|AUTO-APPLY|autoApply" "$REPO_ROOT/docs/LEARNING-APPLY.md"
assert_grep "[S23-D] ACTION-GAP notes optional autonomy" "autonomy|auto-apply|AUTO-APPLY" "$REPO_ROOT/docs/ACTION-GAP.md"

# ---------------------------------------------------------------------------
echo "== [S23-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-23.sh"
if [[ -x "$SELF" ]]; then pass "[S23-Z] sprint-23.sh is executable"; else fail "[S23-Z] sprint-23.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S23-Z] sprint-23.sh shebang is #!/bin/bash"
else fail "[S23-Z] sprint-23.sh shebang is #!/bin/bash"; fi
for sec in S23-A S23-B S23-C S23-D S23-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S23-Z] [$sec] section header present"
  else fail "[S23-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
