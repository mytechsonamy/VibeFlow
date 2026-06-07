#!/bin/bash
# Sprint 34 integration harness — DESIGN-phase guide (design-bootstrap).
#
# Sections:
#   [S34-A] design-bootstrap skill structure + 3-source offer + output contract
#   [S34-B] phase-policy registration + phase-runner DESIGN wiring
#   [S34-C] docs/DESIGN-PHASE.md (Claude-native + both Figma paths)
#   [S34-Z] harness self-audit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }
assert_file() { local l="$1" p="$2"; if [[ -f "$p" ]]; then pass "$l"; else fail "$l (missing: $p)"; fi; }
assert_grep() { local l="$1" pat="$2" f="$3"; if grep -qE "$pat" "$f" 2>/dev/null; then pass "$l"; else fail "$l (no '$pat' in $f)"; fi; }

DB="$REPO_ROOT/skills/design-bootstrap/SKILL.md"
POLICY="$REPO_ROOT/skills/phase-policy.json"
RUNNER="$REPO_ROOT/skills/phase-runner/SKILL.md"
DOC="$REPO_ROOT/docs/DESIGN-PHASE.md"

# ---------------------------------------------------------------------------
echo "== [S34-A] design-bootstrap skill structure =="

assert_file "[S34-A] skills/design-bootstrap/SKILL.md exists" "$DB"
assert_grep "[S34-A] frontmatter name: design-bootstrap" "^name: design-bootstrap$" "$DB"
assert_grep "[S34-A] model-invocable (operator/phase-runner can launch)" "^disable-model-invocation: false$" "$DB"
assert_grep "[S34-A] Phase Contract restricts to DESIGN" "## Phase Contract" "$DB"
assert_grep "[S34-A] DESIGN-only guard" "DESIGN phase only|for the DESIGN phase only|in \\*\\*DESIGN\\*\\* only" "$DB"
# Offers all three sources.
assert_grep "[S34-A] offers Claude-native source" "Claude-native" "$DB"
assert_grep "[S34-A] offers existing-Figma via design-bridge" "design-bridge" "$DB"
assert_grep "[S34-A] offers from-scratch via the official Figma MCP" "official Figma MCP|claude_ai_Figma|use_figma" "$DB"
assert_grep "[S34-A] always asks (no forced default)" "ASK the operator|present the choice every|Do \\*\\*not\\*\\* assume a default" "$DB"
# design-bridge tools wired in allowed-tools.
assert_grep "[S34-A] allowed-tools include design-bridge db_extract_tokens" \
  "mcp__design-bridge__db_extract_tokens" "$DB"
assert_grep "[S34-A] allowed-tools include design-bridge db_generate_styles" \
  "mcp__design-bridge__db_generate_styles" "$DB"
# Output contract: design/ artifacts + consensus marker + breadcrumb.
assert_grep "[S34-A] writes design/design-spec.md (the primary)" "design/design-spec.md" "$DB"
assert_grep "[S34-A] writes design/design-tokens.json" "design/design-tokens.json" "$DB"
assert_grep "[S34-A] arms the consensus marker" "consensus-needed.json" "$DB"
assert_grep "[S34-A] marker primaryArtifact is the design spec" '"primaryArtifact": "design/design-spec.md"' "$DB"
assert_grep "[S34-A] ends with a ▶ Next: breadcrumb" "▶ Next:" "$DB"
assert_grep "[S34-A] accessibility section (feeds accessibility.verified)" "accessibility|WCAG|a11y" "$DB"
# FIGMA_TOKEN setup guidance for the existing-file path.
assert_grep "[S34-A] guides FIGMA_TOKEN / figma_token setup" "FIGMA_TOKEN|figma_token" "$DB"

# ---------------------------------------------------------------------------
echo "== [S34-B] phase-policy + phase-runner wiring =="

if command -v jq >/dev/null 2>&1; then
  if jq -e '.skills["design-bootstrap"].phases | index("DESIGN") != null' "$POLICY" >/dev/null 2>&1; then
    pass "[S34-B] phase-policy registers design-bootstrap for DESIGN"
  else
    fail "[S34-B] phase-policy registers design-bootstrap for DESIGN"
  fi
fi
assert_grep "[S34-B] phase-runner DESIGN row names design-bootstrap" \
  "design-bootstrap" "$RUNNER"
assert_grep "[S34-B] phase-runner DESIGN breadcrumb to design-bootstrap" \
  "/vibeflow:design-bootstrap" "$RUNNER"
assert_grep "[S34-B] phase-runner DESIGN primary is design-spec.md" \
  "design/design-spec.md" "$RUNNER"

# ---------------------------------------------------------------------------
echo "== [S34-C] docs/DESIGN-PHASE.md =="

assert_file "[S34-C] docs/DESIGN-PHASE.md exists" "$DOC"
assert_grep "[S34-C] documents the Claude-native path" "Claude-native" "$DOC"
assert_grep "[S34-C] documents the existing-Figma (design-bridge) path" "design-bridge" "$DOC"
assert_grep "[S34-C] documents the from-scratch (official Figma MCP) path" "official Figma MCP|use_figma" "$DOC"
assert_grep "[S34-C] Figma token connection steps" "Personal access token|figma_token|FIGMA_TOKEN" "$DOC"

# ---------------------------------------------------------------------------
echo "== [S34-Z] harness self-audit =="
SELF="$REPO_ROOT/tests/integration/sprint-34.sh"
assert_grep "[S34-Z] sprint-34.sh runs under set -uo pipefail" '^set -uo pipefail$' "$SELF"
assert_grep "[S34-Z] covers [S34-A]" '\[S34-A\]' "$SELF"
assert_grep "[S34-Z] covers [S34-B]" '\[S34-B\]' "$SELF"
assert_grep "[S34-Z] covers [S34-C]" '\[S34-C\]' "$SELF"

# ---------------------------------------------------------------------------
echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILS[@]}"
  exit 1
fi
exit 0
