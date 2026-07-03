#!/bin/bash
# Sprint 73 integration harness — Claude is always a first-class reviewer in
# headless consensus. When codex/gemini are unavailable, Claude's own review keeps
# the SDLC moving (no stall); when they ARE available, Claude reviews too, as an
# independent "as if a third party wrote it" voice.
#
# Sections:
#   [S73-A] consensus-run.sh: --claude-verdict / VF_CLAUDE_VERDICT_FILE + relaxed exit-3
#   [S73-B] runtime — no CLI + Claude verdict → verdict.json (no stall); no CLI + no Claude → exit 3
#   [S73-C] phase-runner Step 3a forks claude-reviewer + agent fresh-eyes framing
#   [S73-D] docs
#   [S73-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }
assert_eq() { local l="$1" e="$2" a="$3"; if [[ "$e" == "$a" ]]; then pass "$l"; else fail "$l (expected=$e actual=$a)"; fi; }

CRUN="$REPO_ROOT/hooks/scripts/consensus-run.sh"
PR="$REPO_ROOT/skills/phase-runner/SKILL.md"
AGENT="$REPO_ROOT/agents/claude-reviewer.md"
DOC="$REPO_ROOT/docs/CONSENSUS-FLOW.md"

# ---------------------------------------------------------------------------
echo "== [S73-A] consensus-run.sh Claude-reviewer plumbing =="

assert_grep "[S73-A] accepts --claude-verdict arg" "\\-\\-claude-verdict" "$CRUN"
assert_grep "[S73-A] accepts VF_CLAUDE_VERDICT_FILE env" "VF_CLAUDE_VERDICT_FILE" "$CRUN"
assert_grep "[S73-A] records the claude reviewer" "append_cli_verdict claude" "$CRUN"
assert_grep "[S73-A] exit-3 only when NO CLI AND no Claude verdict" 'command -v gemini.*&&.*\[\[ -z .\$CLAUDE_VERDICT. \]\]' "$CRUN"

# ---------------------------------------------------------------------------
echo "== [S73-B] runtime: Claude keeps the panel alive with no external CLI =="

# Build a PATH with everything consensus-run needs EXCEPT codex/gemini, so the
# no-external-CLI path is exercised deterministically on any machine.
BIN="$(mktemp -d)"
for t in bash sh jq date cat mkdir rm grep sed awk find wc tr head tail sort cut basename dirname printf env chmod touch ln mktemp; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t" 2>/dev/null
done
# (codex/gemini deliberately not linked)

DIR="$(mktemp -d)"; mkdir -p "$DIR/docs"
printf '{"project":"t","currentPhase":"REQUIREMENTS"}' > "$DIR/vibeflow.config.json"
printf '# PRD\nrequirements\n' > "$DIR/docs/prd.md"
printf '{"score":72,"verdict":"NEEDS_REVISION","criticalIssues":[{"id":"claude-c1","title":"Missing data-residency control","rationale":"x"}],"suggestions":[{"id":"claude-1","type":"fix","rationale":"add section"}]}' > "$DIR/cv.json"

OUT="$(cd "$DIR" && VIBEFLOW_CWD="$DIR" PATH="$BIN" bash "$CRUN" docs/prd.md --claude-verdict cv.json 2>/dev/null; echo "RC=$?")"
RC="$(printf '%s' "$OUT" | sed -n 's/.*RC=//p')"
JSON_LINE="$(printf '%s' "$OUT" | grep sessionId | head -1)"
assert_eq "[S73-B] no external CLI + Claude verdict → RC 0 (no stall)" "0" "$RC"
assert_eq "[S73-B] verdict status from Claude alone" "NEEDS_REVISION" "$(printf '%s' "$JSON_LINE" | jq -r '.status' 2>/dev/null)"
assert_eq "[S73-B] Claude counted as a reviewer" "1" "$(printf '%s' "$JSON_LINE" | jq -r '.reviewers' 2>/dev/null)"
assert_eq "[S73-B] Claude's critical finding carried (criticalTotal=1)" "1" "$(printf '%s' "$JSON_LINE" | jq -r '.criticalTotal' 2>/dev/null)"

# no CLI AND no Claude verdict → exit 3 (the genuine no-reviewer case)
RC3="$(cd "$DIR" && VIBEFLOW_CWD="$DIR" PATH="$BIN" bash "$CRUN" docs/prd.md >/dev/null 2>&1; echo $?)"
assert_eq "[S73-B] no CLI + no Claude verdict → exit 3" "3" "$RC3"
rm -rf "$DIR" "$BIN"

# ---------------------------------------------------------------------------
echo "== [S73-C] phase-runner + claude-reviewer agent =="

assert_grep "[S73-C] phase-runner Step 3a forks claude-reviewer" "fork the \\*\\*.claude-reviewer. agent" "$PR"
assert_grep "[S73-C] reviews as if a third party wrote it" "as if a third party wrote it" "$PR"
assert_grep "[S73-C] passes the verdict via --claude-verdict" "\\-\\-claude-verdict .vibeflow/state/consensus/claude-review\\.json" "$PR"
assert_grep "[S73-C] Claude is ALWAYS in the panel (no stall)" "Claude is ALWAYS in the panel|no stall, no" "$PR"
assert_grep "[S73-C] exit-3 reinterpreted (only if Claude also absent)" "Exit 3 now only means Claude" "$PR"
assert_grep "[S73-C] agent has the independent/fresh-eyes framing" "as if someone else wrote it" "$AGENT"
assert_grep "[S73-C] agent takes an adversarial stance" "adversarial" "$AGENT"

# ---------------------------------------------------------------------------
echo "== [S73-D] docs =="

assert_grep "[S73-D] CONSENSUS-FLOW.md documents the Claude reviewer fallback" "claude-verdict|Claude.*always.*panel|Claude reviewer.*headless|fresh-eyes" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S73-Z] harness self-audit =="

SELF="$REPO_ROOT/tests/integration/sprint-73.sh"
if head -1 "$SELF" | grep -q '^#!/bin/bash'; then pass "[S73-Z] shebang #!/bin/bash"; else fail "[S73-Z] shebang #!/bin/bash"; fi
for sec in S73-A S73-B S73-C S73-D S73-Z; do
  if grep -q "echo \"== \[$sec\]" "$SELF"; then pass "[S73-Z] [$sec] section header present"; else fail "[S73-Z] [$sec] section header present"; fi
done

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
