#!/bin/bash
# Sprint 25 integration harness — autonomous-loop observability.
#
# Sections:
#   [S25-A] loop-audit.sh reader
#   [S25-B] /vibeflow:status Autonomous Loop section
#   [S25-C] LoopAuditConfigSchema
#   [S25-D] Docs (LOOP-AUDIT.md + refreshes)
#   [S25-Z] Harness self-audit

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

LAUDIT="$REPO_ROOT/hooks/scripts/loop-audit.sh"
STATUS="$REPO_ROOT/skills/status/SKILL.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
CFG_TEST="$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
HOOKT="$REPO_ROOT/hooks/tests/run.sh"

# ---------------------------------------------------------------------------
echo "== [S25-A] loop-audit.sh reader =="

assert_file "[S25-A] hooks/scripts/loop-audit.sh exists" "$LAUDIT"
[[ -x "$LAUDIT" ]] && pass "[S25-A] loop-audit.sh is executable" || fail "[S25-A] loop-audit.sh is executable"
assert_grep "[S25-A] reader is read-only (no Write/cp into config)" "Read-only|read-only" "$LAUDIT"
assert_grep "[S25-A] reads history.jsonl auto-* rows" "auto-apply.*auto-revert.*auto-apply-held|history\\.jsonl" "$LAUDIT"
assert_grep "[S25-A] reads cooldown markers" "cooldown-" "$LAUDIT"
assert_grep "[S25-A] reads the armed watch" "watch\\.json" "$LAUDIT"
assert_grep "[S25-A] computes per-key revertRate" "revertRate" "$LAUDIT"
assert_grep "[S25-A] honours loopAudit.window" "loopAudit\\.window|WINDOW" "$LAUDIT"
assert_grep "[S25-A] degrades to an EMPTY summary" "EMPTY|degrade" "$LAUDIT"

# Runtime: seeded telemetry → correct summary.
RT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s25a-XXXXXX")"
echo '{"project":"s25","currentPhase":"DEVELOPMENT"}' > "$RT/vibeflow.config.json"
CONS="$RT/.vibeflow/state/consensus"; AA="$RT/.vibeflow/state/auto-apply"; REP="$RT/.vibeflow/reports"
mkdir -p "$CONS" "$AA" "$REP"
{ echo '{"type":"auto-apply","key":"consensus.maxIterations"}'
  echo '{"type":"auto-revert","key":"consensus.maxIterations"}'
  echo '{"type":"auto-apply","key":"consensus.maxIterations"}'
  echo '{"type":"auto-revert","key":"consensus.maxIterations"}'; } > "$CONS/history.jsonl"
: > "$AA/cooldown-consensus.maxIterations"
printf '### A\n### B\n' > "$REP/consensus-learning-report.md"
RT_OUT="$(VIBEFLOW_CWD="$RT" bash "$LAUDIT" 2>/dev/null)"
assert_eq "[S25-A] runtime: revertRate computed (=1)" "1" "$(printf '%s' "$RT_OUT" | jq -r '.perKey[0].revertRate')"
assert_eq "[S25-A] runtime: cooledDown reflected" "true" "$(printf '%s' "$RT_OUT" | jq -r '.perKey[0].cooledDown')"
assert_eq "[S25-A] runtime: findingCount=2" "2" "$(printf '%s' "$RT_OUT" | jq -r '.learning.findingCount')"
EMPTY_OUT="$(VIBEFLOW_CWD="$(mktemp -d)" bash "$LAUDIT" 2>/dev/null)"
assert_eq "[S25-A] runtime: empty project applied=0" "0" "$(printf '%s' "$EMPTY_OUT" | jq -r '.autoApply.applied')"
assert_grep "[S25-A] hook tests exercise the reader" "loop-audit\\.sh reader \\[S25-A\\]" "$HOOKT"
rm -rf "$RT"

# ---------------------------------------------------------------------------
echo "== [S25-B] /vibeflow:status Autonomous Loop section =="

assert_grep "[S25-B] status section 6 Autonomous Loop" "Autonomous Loop" "$STATUS"
assert_grep "[S25-B] status runs loop-audit.sh" "loop-audit\\.sh" "$STATUS"
assert_grep "[S25-B] status frontmatter allows the reader" "Bash\\(bash \\*loop-audit" "$STATUS"
assert_grep "[S25-B] status flags revertRate >= 0.5" "revertRate . 0\\.5|revertRate >= 0\\.5|candidate for removal" "$STATUS"
assert_grep "[S25-B] status renders cooled-down keys" "[Cc]ooled-down|cooldowns" "$STATUS"
assert_grep "[S25-B] status renders the armed watch" "armedWatch|armed watch" "$STATUS"
assert_grep "[S25-B] status surfaces the learning finding count" "findingCount|learning report" "$STATUS"
assert_grep "[S25-B] status has an idle collapse" "[Ii]dle collapse|idle .autoApply off|no activity" "$STATUS"

# ---------------------------------------------------------------------------
echo "== [S25-C] LoopAuditConfigSchema =="

assert_grep "[S25-C] config exports LoopAuditConfigSchema" "export const LoopAuditConfigSchema" "$CFG"
assert_grep "[S25-C] window default 20" "window: z.number\\(\\).int\\(\\).*default\\(20\\)|window: 20" "$CFG"
assert_grep "[S25-C] EngineConfigSchema wires loopAudit" "loopAudit: LoopAuditConfigSchema" "$CFG"
assert_grep "[S25-C] loadFileConfig merges loopAudit" "raw\\.loopAudit" "$CFG"
assert_grep "[S25-C] config tests cover LoopAuditConfigSchema" "LoopAuditConfigSchema \\(Sprint 25-C\\)" "$CFG_TEST"

# Runtime: loopAudit.window default via the built engine.
WIN="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.parse({project:"p"}).loopAudit.window));' 2>/dev/null)"
assert_eq "[S25-C] runtime: loopAudit.window defaults to 20" "20" "$WIN"

# ---------------------------------------------------------------------------
echo "== [S25-D] docs =="

assert_file "[S25-D] docs/LOOP-AUDIT.md exists" "$REPO_ROOT/docs/LOOP-AUDIT.md"
assert_grep "[S25-D] LOOP-AUDIT documents the reader sources" "history\\.jsonl|cooldown|watch\\.json" "$REPO_ROOT/docs/LOOP-AUDIT.md"
assert_grep "[S25-D] LOOP-AUDIT documents the JSON contract" "armedWatch|revertRate|perKey" "$REPO_ROOT/docs/LOOP-AUDIT.md"
assert_grep "[S25-D] LOOP-AUDIT documents the idle collapse" "idle|no noise|never errors" "$REPO_ROOT/docs/LOOP-AUDIT.md"
assert_grep "[S25-D] LOOP-AUDIT documents loopAudit.window config" "loopAudit|window" "$REPO_ROOT/docs/LOOP-AUDIT.md"
assert_grep "[S25-D] AUTO-APPLY links the audit surface" "Autonomous Loop|LOOP-AUDIT" "$REPO_ROOT/docs/AUTO-APPLY.md"
assert_grep "[S25-D] META-LEARNING links the audit surface" "Autonomous Loop|LOOP-AUDIT" "$REPO_ROOT/docs/META-LEARNING.md"

# ---------------------------------------------------------------------------
echo "== [S25-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-25.sh"
if [[ -x "$SELF" ]]; then pass "[S25-Z] sprint-25.sh is executable"; else fail "[S25-Z] sprint-25.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S25-Z] sprint-25.sh shebang is #!/bin/bash"
else fail "[S25-Z] sprint-25.sh shebang is #!/bin/bash"; fi
for sec in S25-A S25-B S25-C S25-D S25-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S25-Z] [$sec] section header present"
  else fail "[S25-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
