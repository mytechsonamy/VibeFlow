#!/bin/bash
# Sprint 31 integration harness — onboarding clarity + headless phase-runner.
#
# Sections:
#   [S31-A] rename init → onboard (completeness; no live init-skill refs)
#   [S31-B] ▶ Next: breadcrumb convention on the REQUIREMENTS entry chain
#   [S31-C] consensus-run.sh + aggregator --finalize + gate allowlist + wiring
#   [S31-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_no_grep() { local l="$1" pat="$2" f="$3"; if ! grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l ('$pat' unexpectedly in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

ONBOARD="$REPO_ROOT/skills/onboard/SKILL.md"
PRDQA="$REPO_ROOT/skills/prd-quality-analyzer/SKILL.md"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
CRUN="$REPO_ROOT/hooks/scripts/consensus-run.sh"
CAGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
CGATE="$REPO_ROOT/hooks/scripts/consensus-gate.sh"
SKILL_POLICY="$REPO_ROOT/skills/phase-policy.json"

# ---------------------------------------------------------------------------
echo "== [S31-A] rename init → onboard =="

assert_file "[S31-A] skills/onboard/SKILL.md exists" "$ONBOARD"
if [[ ! -d "$REPO_ROOT/skills/init" ]]; then
  pass "[S31-A] skills/init/ removed"
else
  fail "[S31-A] skills/init/ removed (still present)"
fi
assert_grep "[S31-A] onboard frontmatter name: onboard" "^name: onboard$" "$ONBOARD"
assert_grep "[S31-A] onboard stays disable-model-invocation: true" "^disable-model-invocation: true$" "$ONBOARD"
assert_grep "[S31-A] onboard keeps the Phase Contract" "## Phase Contract" "$ONBOARD"
# Skill registry repointed.
if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills.onboard != null' "$SKILL_POLICY" >/dev/null 2>&1; then
    pass "[S31-A] skills/phase-policy.json registers onboard"
  else
    fail "[S31-A] skills/phase-policy.json registers onboard"
  fi
  if jq -e '.skills.init == null' "$SKILL_POLICY" >/dev/null 2>&1; then
    pass "[S31-A] skills/phase-policy.json no longer registers init"
  else
    fail "[S31-A] skills/phase-policy.json no longer registers init"
  fi
fi

# No LIVE references to the old skill name. Historical records
# (CHANGELOG, release-notes, prior SPRINT docs, this sprint's own plan)
# are allowed to mention it.
LIVE_INIT="$(grep -rln "vibeflow:init" "$REPO_ROOT/skills" "$REPO_ROOT/hooks" 2>/dev/null || true)"
if [[ -z "$LIVE_INIT" ]]; then
  pass "[S31-A] no live skills/ or hooks/ reference /vibeflow:init"
else
  fail "[S31-A] no live /vibeflow:init refs (found: $LIVE_INIT)"
fi
# The load-sdlc-context hint points at onboard now.
assert_grep "[S31-A] load-sdlc-context hints /vibeflow:onboard" \
  "vibeflow:onboard" "$REPO_ROOT/hooks/scripts/load-sdlc-context.sh"

# ---------------------------------------------------------------------------
echo "== [S31-B] ▶ Next: breadcrumb convention =="

assert_grep "[S31-B] onboard ends with a ▶ Next: breadcrumb" "▶ Next:" "$ONBOARD"
assert_grep "[S31-B] onboard breadcrumb names prd-quality-analyzer" \
  "▶ Next: /vibeflow:prd-quality-analyzer" "$ONBOARD"
assert_grep "[S31-B] prd-quality-analyzer has a ▶ Next: breadcrumb" "▶ Next:" "$PRDQA"
assert_grep "[S31-B] prd-quality-analyzer breadcrumb names phase-runner" \
  "▶ Next: /vibeflow:phase-runner" "$PRDQA"
assert_grep "[S31-B] phase-runner emits ▶ Next: breadcrumbs" "▶ Next:" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S31-C] consensus-run.sh + aggregator --finalize + gate + wiring =="

assert_file "[S31-C] consensus-run.sh exists" "$CRUN"
if [[ -x "$CRUN" ]]; then pass "[S31-C] consensus-run.sh is executable"; else fail "[S31-C] consensus-run.sh is executable"; fi
bash -n "$CRUN" 2>/dev/null && pass "[S31-C] consensus-run.sh parses" || fail "[S31-C] consensus-run.sh parses"
assert_grep "[S31-C] consensus-run.sh runs the codex CLI" "codex exec" "$CRUN"
assert_grep "[S31-C] consensus-run.sh runs the gemini CLI" "gemini --model" "$CRUN"
assert_grep "[S31-C] consensus-run.sh finalises via aggregator --finalize" \
  "consensus-aggregator.sh.*--finalize|--finalize" "$CRUN"
assert_grep "[S31-C] consensus-run.sh drains consensus-needed.json" \
  "consensus-needed.json" "$CRUN"
assert_grep "[S31-C] consensus-run.sh exit 3 when no reviewer CLI" "exit 3" "$CRUN"
# Regression pin: the pure-bash watchdog MUST redirect its subshell off the
# captured stdout pipe, else `CMD="$( … | vf_run_timeout … )"` hangs the full
# timeout (~90s) AFTER the CLI already returned. Both copies must carry it.
assert_grep "[S31-C] consensus-run vf_run_timeout watchdog redirected off the capture pipe" \
  '\) >/dev/null 2>&1 & local wd' "$CRUN"
assert_grep "[S31-C] orchestrator vf_run_timeout watchdog redirected off the capture pipe" \
  '\) >/dev/null 2>&1 & local wd' "$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"

# Aggregator gained the additive --finalize mode without breaking the
# SubagentStop path.
assert_grep "[S31-C] aggregator recognises --finalize" '"--finalize"' "$CAGG"
assert_grep "[S31-C] aggregator FINALIZE_MODE guard" "FINALIZE_MODE" "$CAGG"
assert_grep "[S31-C] aggregator skips quorum wait in finalize" \
  'FINALIZE_MODE.*!= .true.*&&.*COUNT < EXPECTED' "$CAGG"
bash -n "$CAGG" 2>/dev/null && pass "[S31-C] aggregator parses" || fail "[S31-C] aggregator parses"

# Gate allowlists the runner.
assert_grep "[S31-C] consensus-gate allowlists consensus-run.sh" \
  '\*consensus-run\.sh\*' "$CGATE"

# phase-runner is wired to call the runner + record consensus, and no
# longer claims to fork the un-forkable orchestrator chain.
assert_grep "[S31-C] phase-runner calls consensus-run.sh" \
  "consensus-run.sh" "$RUNNER"
assert_grep "[S31-C] phase-runner allowed-tools includes consensus-run.sh" \
  "Bash\(bash hooks/scripts/consensus-run.sh" "$RUNNER"
assert_grep "[S31-C] phase-runner records consensus via MCP" \
  "mcp__sdlc-engine__sdlc_record_consensus" "$RUNNER"
assert_no_grep "[S31-C] phase-runner no longer 'invokes consensus-orchestrator' in Step 3" \
  "invoke consensus-orchestrator on the primary artifact" "$RUNNER"

# orchestrator carries the interactive-vs-headless note (links the two).
assert_grep "[S31-C] orchestrator notes the headless equivalent" \
  "consensus-run.sh" "$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"

# Runtime probe: seed two reviewer lines and finalise — verdict.json must
# appear with the right status, WITHOUT a quorum stall.
if command -v jq >/dev/null 2>&1; then
  T="$(mktemp -d)"
  mkdir -p "$T/.vibeflow/state/consensus"
  printf '{"project":"probe","currentPhase":"REQUIREMENTS"}\n' > "$T/vibeflow.config.json"
  SID="probe31"
  LOG="$T/.vibeflow/state/consensus/$SID.jsonl"
  printf '%s\n' '{"recordedAt":"2026-06-06T00:00:00Z","reviewer":"codex","verdict":"APPROVED","criticalIssues":0,"criticalItems":[],"round":1,"note":"","suggestions":[]}' >> "$LOG"
  printf '%s\n' '{"recordedAt":"2026-06-06T00:00:01Z","reviewer":"gemini","verdict":"APPROVED","criticalIssues":0,"criticalItems":[],"round":1,"note":"","suggestions":[]}' >> "$LOG"
  printf 'docs/PRD.md\n' > "$T/.vibeflow/state/consensus/$SID.primary.txt"
  printf '1\n' > "$T/.vibeflow/state/consensus/$SID.current-round.txt"
  VIBEFLOW_CWD="$T" bash "$CAGG" --finalize "$SID" 1 >/dev/null 2>&1
  VF="$T/.vibeflow/state/consensus/$SID.verdict.json"
  if [[ -f "$VF" ]]; then
    pass "[S31-C] runtime: --finalize wrote verdict.json"
    assert_eq "[S31-C] runtime: finalize status APPROVED (2-AI panel)" \
      "APPROVED" "$(jq -r '.status' "$VF" 2>/dev/null)"
    assert_eq "[S31-C] runtime: finalize total=2 (no quorum stall)" \
      "2" "$(jq -r '.total' "$VF" 2>/dev/null)"
    HIST="$T/.vibeflow/state/consensus/history.jsonl"
    if [[ -s "$HIST" ]]; then
      pass "[S31-C] runtime: --finalize appended a history row"
    else
      fail "[S31-C] runtime: --finalize appended a history row"
    fi
  else
    fail "[S31-C] runtime: --finalize wrote verdict.json"
  fi
  # Regression: a normal SubagentStop call (no --finalize) still ingests
  # one reviewer and does NOT crash.
  SID2="probe31b"
  printf '%s' '{"session_id":"'$SID2'","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"{\"verdict\":\"APPROVED\",\"criticalIssues\":0}"}]}}' \
    | VIBEFLOW_CWD="$T" bash "$CAGG" >/dev/null 2>&1
  if [[ -f "$T/.vibeflow/state/consensus/$SID2.jsonl" ]]; then
    pass "[S31-C] runtime: SubagentStop path still logs a reviewer (unbroken)"
  else
    fail "[S31-C] runtime: SubagentStop path still logs a reviewer (unbroken)"
  fi
  rm -rf "$T"

  # End-to-end no-hang probe: with fake fast reviewer CLIs, consensus-run.sh
  # must finish ~instantly and exit 0. If the vf_run_timeout watchdog
  # regresses (holds the capture pipe), the run hangs the full 90s/CLI — so
  # we cap it: run in the background, give it 20s, then check. A fast finish
  # leaves a `.done` marker; a hang leaves none → fail (never hangs the suite).
  T2="$(mktemp -d)"; B2="$T2/bin"; mkdir -p "$B2" "$T2/proj/docs" "$T2/proj/.vibeflow/state"
  printf '# PRD\n\nGereksinim.\n' > "$T2/proj/docs/PRD.md"
  printf '{"project":"p","currentPhase":"REQUIREMENTS"}\n' > "$T2/proj/vibeflow.config.json"
  printf '{"primaryArtifact":"docs/PRD.md","evidence":[],"createdBy":"prd-quality-analyzer"}\n' \
    > "$T2/proj/.vibeflow/state/consensus-needed.json"
  printf '#!/bin/bash\ncat >/dev/null\necho %s\n' "'{\"verdict\":\"APPROVED\",\"criticalIssues\":0}'" > "$B2/codex"
  printf '#!/bin/bash\ncat >/dev/null\necho %s\n' "'{\"verdict\":\"APPROVED\",\"criticalIssues\":0}'" > "$B2/gemini"
  chmod +x "$B2/codex" "$B2/gemini"
  (
    cd "$T2/proj" && PATH="$B2:$PATH" VIBEFLOW_CWD="$T2/proj" \
      bash "$CRUN" .vibeflow/state/consensus-needed.json >/dev/null 2>&1
    touch "$T2/.done"
  ) &
  PROBE_PID=$!
  for _i in $(seq 1 20); do [[ -f "$T2/.done" ]] && break; sleep 1; done
  if [[ -f "$T2/.done" ]]; then
    pass "[S31-C] runtime: consensus-run.sh finishes fast (no watchdog pipe-hang)"
    if [[ -f "$T2/proj/.vibeflow/state/consensus/"*verdict.json ]] 2>/dev/null || ls "$T2/proj/.vibeflow/state/consensus/"*verdict.json >/dev/null 2>&1; then
      pass "[S31-C] runtime: consensus-run.sh wrote a verdict.json"
    else
      fail "[S31-C] runtime: consensus-run.sh wrote a verdict.json"
    fi
    if [[ ! -f "$T2/proj/.vibeflow/state/consensus-needed.json" ]]; then
      pass "[S31-C] runtime: consensus-run.sh drained the consensus marker"
    else
      fail "[S31-C] runtime: consensus-run.sh drained the consensus marker"
    fi
  else
    fail "[S31-C] runtime: consensus-run.sh finishes fast (no watchdog pipe-hang)"
    kill "$PROBE_PID" 2>/dev/null; pkill -P "$PROBE_PID" 2>/dev/null
  fi
  rm -rf "$T2"
fi

# ---------------------------------------------------------------------------
echo "== [S31-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-31.sh"
assert_grep "[S31-Z] sprint-31.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S31-Z] covers [S31-A]" '\[S31-A\]' "$SELF"
assert_grep "[S31-Z] covers [S31-B]" '\[S31-B\]' "$SELF"
assert_grep "[S31-Z] covers [S31-C]" '\[S31-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
