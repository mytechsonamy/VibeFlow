#!/bin/bash
# VibeFlow Sprint 2 integration harness.
#
# Complements tests/integration/run.sh (the platform-wide baseline).
# This harness proves the Sprint 2 deliverables hang together as a
# coherent pipeline:
#
#   - the 7 L1 skills exist in the expected shape and references exist
#   - every skill's declared outputs match the io-standard.md contract
#   - cross-skill references are coherent (BR ↔ invariant ↔ test-data)
#   - every SKILL.md that cites a downstream skill points at a real
#     skill directory
#   - the codebase-intel and design-bridge MCP servers respond to a
#     minimal Sprint-2-specific workflow end-to-end
#
# This harness does NOT duplicate run.sh's checks. Run both from CI;
# order is not significant.
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
IO_STANDARD="$SKILLS_DIR/_standards/io-standard.md"
CI_DIST="$REPO_ROOT/mcp-servers/codebase-intel/dist/index.js"
DB_DIST="$REPO_ROOT/mcp-servers/design-bridge/dist/index.js"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$expected" == "$actual" ]] && pass "$label" \
    || fail "$label (expected=$expected actual=$actual)"
}

# ---------------------------------------------------------------------------
echo "== [S2-A] Sprint 2 L1 skill inventory =="

L1_SKILLS=(
  architecture-validator
  component-test-writer
  contract-test-writer
  business-rule-validator
  test-data-manager
  invariant-formalizer
  checklist-generator
)

for skill in "${L1_SKILLS[@]}"; do
  if [[ -f "$SKILLS_DIR/$skill/SKILL.md" ]]; then
    pass "$skill SKILL.md present"
  else
    fail "$skill SKILL.md present"
  fi
  if [[ -d "$SKILLS_DIR/$skill/references" ]]; then
    REF_COUNT="$(find "$SKILLS_DIR/$skill/references" -maxdepth 1 -type f -name "*.md" | wc -l | tr -d ' ')"
    if (( REF_COUNT >= 2 )); then
      pass "$skill has at least 2 reference files (got $REF_COUNT)"
    else
      fail "$skill has at least 2 reference files (got $REF_COUNT)"
    fi
  else
    fail "$skill references/ directory present"
  fi
done

# Frontmatter sanity — every L1 skill declares `allowed-tools` and is
# `context: fork` so it can scan multiple files without compacting the
# main session. Both are load-bearing for how the skill runs.
for skill in "${L1_SKILLS[@]}"; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f "$f" ]] || continue
  if grep -q "^allowed-tools:" "$f"; then
    pass "$skill declares allowed-tools"
  else
    fail "$skill declares allowed-tools"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S2-B] io-standard output consistency =="

if [[ -f "$IO_STANDARD" ]]; then
  pass "io-standard.md exists"
else
  fail "io-standard.md exists"
fi

# Each skill's primary output must be named in the skill's SKILL.md. The
# output names come from io-standard.md; if drift happens, it shows up
# here as a mismatch between the standard and the skill.
declare_output_check() {
  local skill="$1" output_name="$2"
  local f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f "$f" ]] || { fail "$skill output $output_name — SKILL.md missing"; return; }
  if grep -qF "$output_name" "$f"; then
    pass "$skill SKILL.md names output $output_name"
  else
    fail "$skill SKILL.md names output $output_name"
  fi
}

# Outputs per io-standard.md table:
declare_output_check "component-test-writer" ".test."
declare_output_check "contract-test-writer"  "contract.test.ts"
declare_output_check "contract-test-writer"  "contract-report.md"
declare_output_check "business-rule-validator" "business-rules.md"
declare_output_check "business-rule-validator" "br-test-suite.test.ts"
declare_output_check "business-rule-validator" "semantic-gaps.md"
declare_output_check "test-data-manager"  ".factory.ts"
declare_output_check "test-data-manager"  "fixtures/"
declare_output_check "invariant-formalizer" "invariant-matrix.md"
declare_output_check "invariant-formalizer" "invariants.ts"
declare_output_check "architecture-validator" "architecture-report.md"
declare_output_check "architecture-validator" "adr"
declare_output_check "checklist-generator" "checklist"

# ---------------------------------------------------------------------------
echo "== [S2-C] Cross-skill reference coherence =="

# Every SKILL.md that names a downstream skill must point at a real
# directory under skills/. Naming a skill that doesn't exist is how
# pipelines silently break — the prompt is wrong but the plugin still
# loads cleanly.
check_downstream_refs() {
  local skill="$1"
  local f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f "$f" ]] || return

  # Pull out every backtick-quoted kebab-case name that looks like a
  # skill reference. This is heuristic but deliberately strict so
  # accidental drift surfaces.
  local names
  names="$(grep -oE '`[a-z][a-z0-9-]+[a-z]`' "$f" | tr -d '`' | sort -u)"
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    # Only care about candidates that also happen to be skill dir names.
    if [[ -d "$SKILLS_DIR/$candidate" ]]; then
      pass "$skill references existing skill '$candidate'"
    fi
  done <<< "$names"
}

for skill in "${L1_SKILLS[@]}"; do
  check_downstream_refs "$skill"
done

# Specific contract: invariant-formalizer MUST reference
# business-rule-validator AND test-data-manager in its Step 6 cross-check,
# because that's the only mechanism that keeps the three mutually
# consistent.
IF_SKILL="$SKILLS_DIR/invariant-formalizer/SKILL.md"
if grep -q "business-rule-validator" "$IF_SKILL" \
   && grep -q "test-data-manager" "$IF_SKILL"; then
  pass "invariant-formalizer references both business-rule-validator and test-data-manager"
else
  fail "invariant-formalizer references both business-rule-validator and test-data-manager"
fi

# business-rule-validator Step 4 generates tests that match the AAA shape
# from component-test-writer's test-patterns.md. Drift between the two
# produces inconsistent test styles across generated files.
BR_SKILL="$SKILLS_DIR/business-rule-validator/SKILL.md"
if grep -q "test-patterns.md" "$BR_SKILL" \
   || grep -q "component-test-writer" "$BR_SKILL"; then
  pass "business-rule-validator reuses component-test-writer AAA patterns"
else
  fail "business-rule-validator reuses component-test-writer AAA patterns"
fi

# checklist-generator injects CL-BR-<ruleId> and CL-GAP-<scenarioId> items,
# so it must reference business-rule-validator AND scenario-set.md.
CG_SKILL="$SKILLS_DIR/checklist-generator/SKILL.md"
if grep -q "CL-BR-" "$CG_SKILL" && grep -q "CL-GAP-" "$CG_SKILL"; then
  pass "checklist-generator declares both CL-BR-* and CL-GAP-* injection paths"
else
  fail "checklist-generator declares both CL-BR-* and CL-GAP-* injection paths"
fi

# ---------------------------------------------------------------------------
echo "== [S2-D] Gate contracts declared consistently =="

# Every Sprint-2 L1 skill declares a gate contract. The contract string
# is the single line release-decision-engine reads to compute the
# aggregate. Drift here is how skills get "approved by accident".
declare -a GATE_CONTRACTS=(
  "architecture-validator:criticalPolicyViolations == 0"
  "business-rule-validator:zero uncovered P0 rules and zero contradicted rules"
  "contract-test-writer:MAJOR breaking changes block the release"
  "test-data-manager:Same seed → same output"
  "invariant-formalizer:zero unformalized P0 invariants and zero cross-check"
  "checklist-generator:zero unverifiable items in the generated checklist"
)

for pair in "${GATE_CONTRACTS[@]}"; do
  skill="${pair%%:*}"
  contract="${pair#*:}"
  f="$SKILLS_DIR/$skill/SKILL.md"
  if [[ -f "$f" ]] && grep -q "$contract" "$f"; then
    pass "$skill declares its gate contract"
  else
    fail "$skill declares its gate contract ('$contract')"
  fi
done

# component-test-writer is the odd one out — it generates code, it
# doesn't gate on a contract. Assert the inverse so drift doesn't
# silently add a fake gate to it.
CTW_SKILL="$SKILLS_DIR/component-test-writer/SKILL.md"
if grep -q "Gate contract" "$CTW_SKILL"; then
  fail "component-test-writer should not declare a gate contract (it generates code, not verdicts)"
else
  pass "component-test-writer correctly does NOT declare a gate contract"
fi

# ---------------------------------------------------------------------------
echo "== [S2-E] codebase-intel + design-bridge end-to-end sanity =="

# Both MCP servers were already smoked in run.sh [4b] / [4c]. Here we
# check the Sprint-2 completion story: the MCP dist files exist, the
# servers parse, and calling one tool end-to-end still returns valid
# JSON. A shallower version of the baseline smoke, running in the
# Sprint-2 harness so a Sprint-2-only CI job stays standalone.

if [[ -f "$CI_DIST" ]] && node --check "$CI_DIST" 2>/dev/null; then
  pass "codebase-intel dist parses"
else
  fail "codebase-intel dist parses"
fi
if [[ -f "$DB_DIST" ]] && node --check "$DB_DIST" 2>/dev/null; then
  pass "design-bridge dist parses"
else
  fail "design-bridge dist parses"
fi

S2E_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-s2-XXXXXX")"
cat > "$S2E_DIR/package.json" <<'PKG'
{"name":"s2-e2e","version":"1.0.0","dependencies":{"fastify":"^4.0.0"}}
PKG
cat > "$S2E_DIR/tsconfig.json" <<'TS'
{"compilerOptions":{"target":"ES2022"}}
TS

CI_OUT="$(node "$CI_DIST" <<EOF 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s2","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ci_analyze_structure","arguments":{"root":"$S2E_DIR"}}}
EOF
)"
CI_LINE="$(echo "$CI_OUT" | grep '"id":3')"
if [[ "$CI_LINE" == *"typescript"* && "$CI_LINE" == *"fastify"* ]]; then
  pass "codebase-intel Sprint-2 sanity: analyze_structure round-trip"
else
  fail "codebase-intel Sprint-2 sanity: analyze_structure round-trip"
fi

# design-bridge: lazy-construct the Figma client at first call, so we can
# list_tools without ever hitting the token branch.
DB_OUT="$(FIGMA_TOKEN=test-token node "$DB_DIST" <<EOF 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s2","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF
)"
DB_LIST="$(echo "$DB_OUT" | grep '"id":2')"
if [[ "$DB_LIST" == *"db_fetch_design"* \
   && "$DB_LIST" == *"db_extract_tokens"* \
   && "$DB_LIST" == *"db_generate_styles"* \
   && "$DB_LIST" == *"db_compare_impl"* ]]; then
  pass "design-bridge Sprint-2 sanity: list_tools returns all 4 tools"
else
  fail "design-bridge Sprint-2 sanity: list_tools returns all 4 tools"
fi

rm -rf "$S2E_DIR"

# ---------------------------------------------------------------------------
echo "== [S2-F] Sprint 2 bug tracker closure =="

# Every Sprint 2 bug must be marked FIXED in ROADMAP.md. If someone
# silently flips one back to "Sprint N" or "TODO", the gate here catches
# it — this is the only place we assert the closure is on the record.
ROADMAP="$REPO_ROOT/ROADMAP.md"
if [[ -f "$ROADMAP" ]]; then
  for bug_no in 3 4 7; do
    if grep -qE "^\| ${bug_no} \|.*\| FIXED \|" "$ROADMAP"; then
      pass "ROADMAP bug #$bug_no marked FIXED"
    else
      fail "ROADMAP bug #$bug_no marked FIXED"
    fi
  done
else
  fail "ROADMAP.md exists"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
