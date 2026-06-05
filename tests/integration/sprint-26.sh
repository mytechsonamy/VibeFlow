#!/bin/bash
# Sprint 26 integration harness — TESTING→DEPLOYMENT consumer hardening
# + two FlowBridge-surfaced consensus-CLI robustness bugs.
#
# Sections:
#   [S26-A] release-decision-engine auto-satisfies release.decision.go (GO only)
#   [S26-B] opt-in entry-criteria enforcement (GatesConfig + validator + wiring)
#   [S26-C] TESTING/DEPLOYMENT pipeline contract (artifacts + auto-satisfy + map)
#   [S26-D] Docs (TESTING-READINESS.md + refreshes)
#   [S26-F] portable timeout (macOS no-timeout) + runtime probe
#   [S26-G] codex stdin/pipe-form footgun fix
#   [S26-Z] Harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_absent() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then fail "$l (found '$pat' in $f)"; else pass "$l"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

RDE="$REPO_ROOT/skills/release-decision-engine/SKILL.md"
ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
CFG="$REPO_ROOT/mcp-servers/sdlc-engine/src/config.ts"
VAL="$REPO_ROOT/mcp-servers/sdlc-engine/src/validation.ts"
ENG="$REPO_ROOT/mcp-servers/sdlc-engine/src/engine.ts"
TOOLS="$REPO_ROOT/mcp-servers/sdlc-engine/src/tools.ts"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"

# ---------------------------------------------------------------------------
echo "== [S26-A] release-decision-engine auto-satisfies release.decision.go =="

assert_grep "[S26-A] satisfies release.decision.go via MCP tool" "sdlc_satisfy_criterion" "$RDE"
assert_grep "[S26-A] criterion is release.decision.go" "release\\.decision\\.go" "$RDE"
assert_grep "[S26-A] GO-only (CONDITIONAL/BLOCKED do not satisfy)" "GO only|GO\\b.*only|do NOT satisfy" "$RDE"
assert_grep "[S26-A] ties into the entry-gate" "enforceEntryCriteria|entry-gate|entry criterion" "$RDE"

# ---------------------------------------------------------------------------
echo "== [S26-B] opt-in entry-criteria enforcement =="

assert_grep "[S26-B] config exports GatesConfigSchema" "export const GatesConfigSchema" "$CFG"
assert_grep "[S26-B] enforceEntryCriteria defaults false" "enforceEntryCriteria: z.boolean\\(\\).default\\(false\\)" "$CFG"
assert_grep "[S26-B] EngineConfigSchema wires gates" "gates: GatesConfigSchema" "$CFG"
assert_grep "[S26-B] loadFileConfig merges gates" "raw\\.gates" "$CFG"
assert_grep "[S26-B] validator accepts enforceEntryCriteria" "enforceEntryCriteria" "$VAL"
assert_grep "[S26-B] validator checks target entryCriteria" "entryCriteria|Entry criteria not met" "$VAL"
assert_grep "[S26-B] engine passes enforceEntryCriteria" "enforceEntryCriteria" "$ENG"
assert_grep "[S26-B] tools inject gates.enforceEntryCriteria" "enforceEntryCriteria: gates\\.enforceEntryCriteria|gates\\.enforceEntryCriteria" "$TOOLS"
assert_grep "[S26-B] config tests cover GatesConfigSchema" "GatesConfigSchema \\(Sprint 26-B\\)" "$REPO_ROOT/mcp-servers/sdlc-engine/tests/config.test.ts"
assert_grep "[S26-B] validation tests cover the entry-gate" "Sprint 26-B" "$REPO_ROOT/mcp-servers/sdlc-engine/tests/validation.test.ts"

# Runtime: default off via the built engine; on requires the entry criterion.
OFF="$(node -e '
  const {EngineConfigSchema}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/config.js");
  process.stdout.write(String(EngineConfigSchema.parse({project:"p"}).gates.enforceEntryCriteria));' 2>/dev/null)"
assert_eq "[S26-B] runtime: enforceEntryCriteria defaults to false" "false" "$OFF"
GATE="$(node -e '
  const {PhaseRegistry}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/phases.js");
  const {PhaseTransitionValidator}=require("'"$REPO_ROOT"'/mcp-servers/sdlc-engine/dist/validation.js");
  const v=new PhaseTransitionValidator(new PhaseRegistry());
  const base={from:"TESTING",to:"DEPLOYMENT",satisfiedCriteria:["coverage.met","mutation.score.acceptable"],lastConsensus:"APPROVED",lastConsensusPhase:"TESTING"};
  const off=v.validate({...base, enforceEntryCriteria:false}).ok;
  const on=v.validate({...base, enforceEntryCriteria:true}).ok;
  const onSat=v.validate({...base, satisfiedCriteria:[...base.satisfiedCriteria,"release.decision.go"], enforceEntryCriteria:true}).ok;
  process.stdout.write(off+":"+on+":"+onSat);' 2>/dev/null)"
assert_eq "[S26-B] runtime: off→advances, on→blocked, on+GO→advances" "true:false:true" "$GATE"

# ---------------------------------------------------------------------------
echo "== [S26-C] TESTING/DEPLOYMENT pipeline contract =="

# Each TESTING/DEPLOYMENT analyzer: artifacts + auto-satisfy + phase-runner map.
for s in coverage-analyzer mutation-test-runner; do
  assert_grep "[S26-C] $s writes .vibeflow/artifacts" "\\.vibeflow/artifacts" "$REPO_ROOT/skills/$s/SKILL.md"
done
assert_grep "[S26-C] coverage-analyzer auto-satisfies coverage.met" "coverage\\.met" "$REPO_ROOT/skills/coverage-analyzer/SKILL.md"
assert_grep "[S26-C] mutation-test-runner auto-satisfies mutation.score.acceptable" "mutation\\.score\\.acceptable" "$REPO_ROOT/skills/mutation-test-runner/SKILL.md"
assert_grep "[S26-C] phase-runner maps TESTING analyzers" "TESTING.*coverage-analyzer.*mutation-test-runner|coverage-analyzer.*mutation-test-runner" "$PR"
assert_grep "[S26-C] phase-runner maps DEPLOYMENT analyzers" "DEPLOYMENT.*release-decision-engine.*deploy-verifier|release-decision-engine.*deploy-verifier" "$PR"
assert_grep "[S26-C] phases tests pin the TESTING contract" "pins the TESTING phase entry/exit" "$REPO_ROOT/mcp-servers/sdlc-engine/tests/phases.test.ts"
assert_grep "[S26-C] phases tests pin the DEPLOYMENT contract" "pins the DEPLOYMENT phase entry/exit" "$REPO_ROOT/mcp-servers/sdlc-engine/tests/phases.test.ts"

# ---------------------------------------------------------------------------
echo "== [S26-D] docs =="

assert_file "[S26-D] docs/TESTING-READINESS.md exists" "$REPO_ROOT/docs/TESTING-READINESS.md"
assert_grep "[S26-D] doc clarifies empty artifacts/ in DEVELOPMENT" "artifacts.*normal|empty.*artifacts|DEVELOPMENT.*normal" "$REPO_ROOT/docs/TESTING-READINESS.md"
assert_grep "[S26-D] doc covers the DEV→TESTING→DEPLOYMENT walk" "TESTING|DEPLOYMENT" "$REPO_ROOT/docs/TESTING-READINESS.md"
assert_grep "[S26-D] doc explains release.decision.go" "release\\.decision\\.go" "$REPO_ROOT/docs/TESTING-READINESS.md"
assert_grep "[S26-D] AUTO-SATISFY adds release.decision.go row" "release\\.decision\\.go" "$REPO_ROOT/docs/AUTO-SATISFY.md"
assert_grep "[S26-D] PHASE-BOUNDARIES documents entry/exit semantics" "entryCriteria|entry criteria|enforceEntryCriteria" "$REPO_ROOT/docs/PHASE-BOUNDARIES.md"

# ---------------------------------------------------------------------------
echo "== [S26-F] portable timeout (macOS no-timeout) =="

assert_grep "[S26-F] orchestrator defines vf_run_timeout" "vf_run_timeout\\(\\)" "$ORCH"
assert_grep "[S26-F] prefers gtimeout when timeout absent" "gtimeout" "$ORCH"
assert_grep "[S26-F] pure-bash watchdog returns 124" "return 124" "$ORCH"
assert_grep "[S26-F] watchdog preserves piped stdin (no /dev/null)" '< "\$_in"|drain the piped prompt|stdin from a temp' "$ORCH"
assert_grep "[S26-F] codex uses vf_run_timeout, not bare timeout" "vf_run_timeout 90 codex" "$ORCH"
assert_grep "[S26-F] gemini uses vf_run_timeout, not bare timeout" "vf_run_timeout 90 gemini" "$ORCH"
assert_absent "[S26-F] no bare 'timeout 90 codex' left" "[^_]timeout 90 codex" "$ORCH"
assert_absent "[S26-F] no bare 'timeout 90 gemini' left" "[^_]timeout 90 gemini" "$ORCH"
assert_grep "[S26-F] allowed-tools include gtimeout" "Bash\\(gtimeout" "$ORCH"

# Runtime: the portable timeout helper, forced down the watchdog path.
TMP="$(mktemp -d)"; cat > "$TMP/t.sh" <<'EOF'
vf_run_timeout() {
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  local _in; _in="$(mktemp)"; cat > "$_in"
  "$@" < "$_in" & local pid=$!
  ( sleep "$secs"; kill -0 "$pid" 2>/dev/null && { touch "/tmp/vf_to_$pid"; kill -TERM "$pid" 2>/dev/null; }; ) & local wd=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill -TERM "$wd" 2>/dev/null; wait "$wd" 2>/dev/null; rm -f "$_in"
  if [[ -f "/tmp/vf_to_$pid" ]]; then rm -f "/tmp/vf_to_$pid"; return 124; fi
  return "$rc"
}
O=$(echo hi | vf_run_timeout 5 cat); echo "pipe:$O:rc$?"
vf_run_timeout 1 sleep 5; echo "slow:rc$?"
vf_run_timeout 5 bash -c 'exit 3'; echo "err:rc$?"
EOF
RT_OUT="$(PATH="/usr/bin:/bin" bash "$TMP/t.sh" 2>/dev/null)"
echo "$RT_OUT" | grep -q "pipe:hi:rc0" && pass "[S26-F] runtime: piped fast cmd → rc 0 (EOF-safe)" || fail "[S26-F] runtime: piped fast cmd → rc 0 (EOF-safe)"
echo "$RT_OUT" | grep -q "slow:rc124" && pass "[S26-F] runtime: hang → 124 (watchdog, cli_timeout)" || fail "[S26-F] runtime: hang → 124 (watchdog, cli_timeout)"
echo "$RT_OUT" | grep -q "err:rc3" && pass "[S26-F] runtime: genuine error → its rc, not 124" || fail "[S26-F] runtime: genuine error → its rc, not 124"
rm -rf "$TMP"

# ---------------------------------------------------------------------------
echo "== [S26-G] codex stdin/pipe-form footgun =="

assert_absent "[S26-G] no hanging argument form 'codex exec \"\$(cat'" 'codex exec "\$\(cat' "$ORCH"
assert_grep "[S26-G] example uses the pipe form" "build_review_prompt \\| codex exec|\\| codex exec" "$ORCH"
assert_grep "[S26-G] warns: always pipe, never argument" "always PIPE|never pass it as an argument|hangs" "$ORCH"

# ---------------------------------------------------------------------------
echo "== [S26-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-26.sh"
if [[ -x "$SELF" ]]; then pass "[S26-Z] sprint-26.sh is executable"; else fail "[S26-Z] sprint-26.sh is executable"; fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S26-Z] sprint-26.sh shebang is #!/bin/bash"
else fail "[S26-Z] sprint-26.sh shebang is #!/bin/bash"; fi
for sec in S26-A S26-B S26-C S26-D S26-F S26-G S26-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S26-Z] [$sec] section header present"
  else fail "[S26-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
