#!/bin/bash
# Sprint 37 integration harness — architecture-bootstrap (author-side ARCHITECTURE
# guide) + the phase-runner "run analyzers as skills, not general agents" fix.
#
# Sections:
#   [S37-A] architecture-bootstrap skill structure
#   [S37-B] phase-policy + phase-runner wiring (+ Skill-not-Agent fix)
#   [S37-C] docs/ARCHITECTURE-PHASE.md
#   [S37-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

AB="$REPO_ROOT/skills/architecture-bootstrap/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
DOC="$REPO_ROOT/docs/ARCHITECTURE-PHASE.md"

# ---------------------------------------------------------------------------
echo "== [S37-A] architecture-bootstrap skill structure =="

assert_file "[S37-A] skills/architecture-bootstrap/SKILL.md exists" "$AB"
assert_grep "[S37-A] frontmatter name: architecture-bootstrap" "^name: architecture-bootstrap$" "$AB"
assert_grep "[S37-A] model-invocable" "^disable-model-invocation: false$" "$AB"
assert_grep "[S37-A] Phase Contract restricts to ARCHITECTURE" "## Phase Contract" "$AB"
assert_grep "[S37-A] ARCHITECTURE-only guard" "ARCHITECTURE phase only|in \\*\\*ARCHITECTURE\\*\\* only" "$AB"
# Asks the technology baseline (3 options).
assert_grep "[S37-A] asks the technology/deployment baseline" "technology / deployment baseline|technology baseline" "$AB"
assert_grep "[S37-A] option propose-sensible-defaults" "Propose sensible defaults" "$AB"
assert_grep "[S37-A] option specify-the-stack" "specify the stack|I'll specify" "$AB"
assert_grep "[S37-A] option stack-agnostic" "Stack-agnostic|stack-agnostic" "$AB"
# Authors the artifacts.
assert_grep "[S37-A] authors docs/architecture.md (the primary)" "docs/architecture.md" "$AB"
assert_grep "[S37-A] authors ADRs (docs/adr/ADR-NNN)" "docs/adr/ADR-NNN|ADR-NNN-" "$AB"
assert_grep "[S37-A] security architecture is domain-policy-aware" "domain-policy-aware|criticalPolicyViolations|silent on" "$AB"
assert_grep "[S37-A] names financial policy areas (encryption/audit/RLS/kill-switch)" \
  "at-rest encryption|RLS|kill-switch|WORM" "$AB"
# Output contract.
assert_grep "[S37-A] arms the consensus marker" "consensus-needed.json" "$AB"
assert_grep "[S37-A] marker primaryArtifact is the architecture doc" '"primaryArtifact": "docs/architecture.md"' "$AB"
assert_grep "[S37-A] ends with a ▶ Next: breadcrumb" "▶ Next:" "$AB"
assert_grep "[S37-A] brownfield import graph via codebase-intel" "ci_dependency_graph" "$AB"

# ---------------------------------------------------------------------------
echo "== [S37-B] phase-policy + phase-runner wiring =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["architecture-bootstrap"].phases | index("ARCHITECTURE") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S37-B] phase-policy registers architecture-bootstrap for ARCHITECTURE"
  else
    fail "[S37-B] phase-policy registers architecture-bootstrap for ARCHITECTURE"
  fi
fi
assert_grep "[S37-B] phase-runner ARCHITECTURE row names architecture-bootstrap" \
  "architecture-bootstrap" "$RUNNER"
assert_grep "[S37-B] phase-runner breadcrumbs to architecture-bootstrap" \
  "/vibeflow:architecture-bootstrap" "$RUNNER"
# The Skill-not-Agent fix (FlowBridge: validator returned exploration).
assert_grep "[S37-B] Step 2 says run analyzers via the Skill tool, not a general agent" \
  "use the Skill tool|Skill, not agent|Do NOT spawn a general-purpose" "$RUNNER"
assert_grep "[S37-B] Step 2 warns Explore/general agent returns exploration not validation" \
  "exploration.*not the analyzer|general/Explore subagent|returns codebase" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S37-C] docs/ARCHITECTURE-PHASE.md =="

assert_file "[S37-C] docs/ARCHITECTURE-PHASE.md exists" "$DOC"
assert_grep "[S37-C] documents author-then-validate" "author.*then validate|authored before|architecture-bootstrap" "$DOC"
assert_grep "[S37-C] documents the 3 baseline options" "Propose sensible defaults|specify the stack|Stack-agnostic" "$DOC"
assert_grep "[S37-C] notes phase-runner runs analyzers as skills not agents" \
  "skills, not agents|Skill tool|never by.*spawning" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S37-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-37.sh"
assert_grep "[S37-Z] sprint-37.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S37-Z] covers [S37-A]" '\[S37-A\]' "$SELF"
assert_grep "[S37-Z] covers [S37-B]" '\[S37-B\]' "$SELF"
assert_grep "[S37-Z] covers [S37-C]" '\[S37-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
