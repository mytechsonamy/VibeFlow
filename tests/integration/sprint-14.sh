#!/bin/bash
# Sprint 14 integration harness — consensus flow + mode retirement + skill
# output contract. Pins the behaviour changes so a future refactor can't
# silently regress.
#
# Sections:
#   [S14-A] consensus-aggregator uses CLI-availability + config override
#   [S14-B] non-reviewer subagents are filtered out (reviewer=unknown bug)
#   [S14-C] mode concept fully retired
#   [S14-D] skill output contract — Write + explicit .vibeflow/reports path
#   [S14-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

# ---------------------------------------------------------------------------
echo "== [S14-A] consensus-aggregator CLI-availability quorum =="

AGG="$REPO_ROOT/hooks/scripts/consensus-aggregator.sh"
if grep -q 'consensus.quorum' "$AGG"; then
  pass "[S14-A] aggregator honours consensus.quorum config override"
else
  fail "[S14-A] aggregator honours consensus.quorum config override"
fi
if grep -q 'command -v codex' "$AGG" && grep -q 'command -v gemini' "$AGG"; then
  pass "[S14-A] aggregator detects codex + gemini CLIs for default quorum"
else
  fail "[S14-A] aggregator detects codex + gemini CLIs for default quorum"
fi
if ! grep -qE '\bvf_mode\b' "$AGG"; then
  pass "[S14-A] aggregator no longer reads vf_mode"
else
  fail "[S14-A] aggregator no longer reads vf_mode"
fi

TRIG="$REPO_ROOT/hooks/scripts/trigger-ai-review.sh"
if ! grep -qE 'MODE.*==.*solo' "$TRIG"; then
  pass "[S14-A] trigger-ai-review has no 'MODE == solo' gate"
else
  fail "[S14-A] trigger-ai-review has no 'MODE == solo' gate"
fi

ORCH="$REPO_ROOT/skills/consensus-orchestrator/SKILL.md"
if ! grep -q 'Team Mode Only' "$ORCH"; then
  pass "[S14-A] consensus-orchestrator skill no longer says Team Mode Only"
else
  fail "[S14-A] consensus-orchestrator skill no longer says Team Mode Only"
fi
if grep -q 'CLI-availability only' "$ORCH"; then
  pass "[S14-A] consensus-orchestrator skill documents CLI-availability gate"
else
  fail "[S14-A] consensus-orchestrator skill documents CLI-availability gate"
fi

# ---------------------------------------------------------------------------
echo "== [S14-B] aggregator filters non-reviewer subagents =="

if grep -q 'case "\$SUBAGENT"' "$AGG"; then
  pass "[S14-B] aggregator branches on subagent name"
else
  fail "[S14-B] aggregator branches on subagent name"
fi
for pattern in 'claude-reviewer' 'reviewer' '\\*-reviewer' 'consensus-\\*'; do
  if grep -qE "$pattern" "$AGG"; then
    pass "[S14-B] aggregator allow-list covers '$pattern'"
  else
    fail "[S14-B] aggregator allow-list covers '$pattern'"
  fi
done

# Runtime: a non-reviewer subagent (e.g. Explore) must not create a
# verdict log entry.
if command -v jq >/dev/null 2>&1; then
  S14B_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s14b-XXXXXX")"
  cat > "$S14B_DIR/vibeflow.config.json" <<EOF
{"project":"t","domain":"general","currentPhase":"DEVELOPMENT"}
EOF
  mkdir -p "$S14B_DIR/.vibeflow"
  export VIBEFLOW_CWD="$S14B_DIR"
  INPUT='{"session_id":"sx","subagent_type":"Explore","tool_response":{"content":[{"text":"APPROVED"}]}}'
  printf '%s' "$INPUT" | bash "$AGG" >/dev/null 2>&1
  if [[ ! -f "$S14B_DIR/.vibeflow/state/consensus/sx.jsonl" ]]; then
    pass "[S14-B] Explore subagent output does not pollute verdict log"
  else
    fail "[S14-B] Explore subagent output does not pollute verdict log"
  fi
  unset VIBEFLOW_CWD
  rm -rf "$S14B_DIR"
fi

# ---------------------------------------------------------------------------
echo "== [S14-C] mode concept fully retired =="

LIB="$REPO_ROOT/hooks/scripts/_lib.sh"
if ! grep -qE '^vf_mode\(\)\s*\{' "$LIB"; then
  pass "[S14-C] _lib.sh no longer defines vf_mode()"
else
  fail "[S14-C] _lib.sh no longer defines vf_mode()"
fi

for hook in load-sdlc-context.sh compact-recovery.sh trigger-ai-review.sh consensus-aggregator.sh; do
  if ! grep -qE '^MODE=|vf_mode' "$REPO_ROOT/hooks/scripts/$hook"; then
    pass "[S14-C] $hook no longer reads MODE"
  else
    fail "[S14-C] $hook no longer reads MODE"
  fi
done

# Status line + compact recovery no longer print `mode=`.
if ! grep -q 'mode=$MODE' "$REPO_ROOT/hooks/scripts/load-sdlc-context.sh"; then
  pass "[S14-C] load-sdlc-context status line has no mode="
else
  fail "[S14-C] load-sdlc-context status line has no mode="
fi

# Every committed vibeflow.config.json is free of mode.
for cfg in "$REPO_ROOT/vibeflow.config.json" "$REPO_ROOT"/examples/*/vibeflow.config.json; do
  [[ -f "$cfg" ]] || continue
  if ! grep -qE '"mode"\s*:' "$cfg"; then
    pass "[S14-C] $(basename "$(dirname "$cfg")")/$(basename "$cfg") has no mode field"
  else
    fail "[S14-C] $(basename "$(dirname "$cfg")")/$(basename "$cfg") has no mode field"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S14-D] skill output contract =="

# For every skill with an "Output Files" section we assert:
#   1. Write (or MultiEdit) is in allowed-tools
#   2. At least one "\.vibeflow/reports/" path is explicitly named
for skill_md in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$skill_md")")"
  if ! grep -qE '^## Output Files' "$skill_md"; then
    continue
  fi
  if grep -qE '^allowed-tools:.*(Write|MultiEdit)' "$skill_md"; then
    pass "[S14-D] $name has Write in allowed-tools"
  else
    fail "[S14-D] $name has Write in allowed-tools"
  fi
  if grep -qE '\.vibeflow/reports/' "$skill_md"; then
    pass "[S14-D] $name names at least one .vibeflow/reports/ path"
  else
    fail "[S14-D] $name names at least one .vibeflow/reports/ path"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S14-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-14.sh"
if [[ -x "$SELF" ]]; then
  pass "[S14-Z] sprint-14.sh is executable"
else
  fail "[S14-Z] sprint-14.sh is executable"
fi
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then
  pass "[S14-Z] sprint-14.sh shebang is #!/bin/bash"
else
  fail "[S14-Z] sprint-14.sh shebang is #!/bin/bash"
fi
for sec in "S14-A" "S14-B" "S14-C" "S14-D" "S14-Z"; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then
    pass "[S14-Z] [$sec] section header present"
  else
    fail "[S14-Z] [$sec] section header present"
  fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
