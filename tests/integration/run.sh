#!/bin/bash
# VibeFlow integration test harness.
#
# Runs from anywhere. Covers the things unit tests can't:
#  1. Plugin manifest + skill discoverability (static checks)
#  2. hooks.json references every script that actually exists
#  3. .mcp.json references a built dist that actually loads
#  4. sdlc-engine stdio smoke test (ListTools + CallTool via JSON-RPC)
#  5. End-to-end flow: engine advance → load-sdlc-context + commit-guard react
#
# Deliberately does NOT attempt to spawn Claude Code — that's out of scope
# for CI. The plugin-load smoke test lives in test 1 (structural validation).
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
MCP_JSON="$REPO_ROOT/.mcp.json"
ENGINE_DIST="$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js"
CI_DIST="$REPO_ROOT/mcp-servers/codebase-intel/dist/index.js"
DB_DIST="$REPO_ROOT/mcp-servers/design-bridge/dist/index.js"
DO_DIST="$REPO_ROOT/mcp-servers/dev-ops/dist/index.js"
OB_DIST="$REPO_ROOT/mcp-servers/observability/dist/index.js"

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

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  [[ "$haystack" == *"$needle"* ]] && pass "$label" \
    || fail "$label (no '$needle' in output)"
}

# ---------------------------------------------------------------------------
echo "== [1] plugin + skill manifest =="

if [[ -f "$PLUGIN_JSON" ]]; then
  if jq -e . "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "plugin.json is valid JSON"
  else
    fail "plugin.json is valid JSON"
  fi
  NAME="$(jq -r .name "$PLUGIN_JSON")"
  assert_eq "plugin.name is vibeflow" "vibeflow" "$NAME"
  SKILLS_DIR_REL="$(jq -r .skills "$PLUGIN_JSON")"
  SKILLS_DIR="$REPO_ROOT/${SKILLS_DIR_REL#./}"
  [[ -d "$SKILLS_DIR" ]] && pass "plugin.skills directory exists" \
    || fail "plugin.skills directory exists ($SKILLS_DIR)"
else
  fail "plugin.json exists at $PLUGIN_JSON"
fi

# Every skill dir must have a SKILL.md with valid frontmatter.
MISSING_SKILL=0
BAD_FRONTMATTER=0
for d in "$SKILLS_DIR"/*/; do
  name="$(basename "$d")"
  [[ "$name" == "_standards" ]] && continue
  if [[ ! -f "$d/SKILL.md" ]]; then
    MISSING_SKILL=$((MISSING_SKILL + 1))
    echo "    missing SKILL.md: $name"
    continue
  fi
  # Frontmatter must start with ---, contain name: and description:.
  head -1 "$d/SKILL.md" | grep -q '^---$' || {
    BAD_FRONTMATTER=$((BAD_FRONTMATTER + 1))
    echo "    missing frontmatter opener: $name"
    continue
  }
  grep -q '^name:' "$d/SKILL.md" && grep -q '^description:' "$d/SKILL.md" || {
    BAD_FRONTMATTER=$((BAD_FRONTMATTER + 1))
    echo "    incomplete frontmatter: $name"
  }
done
assert_eq "every skill dir has SKILL.md" "0" "$MISSING_SKILL"
assert_eq "every SKILL.md has name+description frontmatter" "0" "$BAD_FRONTMATTER"

# architecture-validator (S2-04) lives with a references/ sidecar. The skill
# breaks if either the catalog or the ADR template drifts away.
AV_SKILL="$SKILLS_DIR/architecture-validator"
[[ -f "$AV_SKILL/SKILL.md" ]] && pass "architecture-validator SKILL.md present" \
  || fail "architecture-validator SKILL.md present"
[[ -f "$AV_SKILL/references/policy-catalog.md" ]] \
  && pass "architecture-validator policy-catalog.md present" \
  || fail "architecture-validator policy-catalog.md present"
[[ -f "$AV_SKILL/references/adr-template.md" ]] \
  && pass "architecture-validator adr-template.md present" \
  || fail "architecture-validator adr-template.md present"

# Every domain the engine supports must have at least one policy row
# in the catalog. If a domain ships without rules the validator silently
# degrades to "general" and the gate becomes meaningless.
AV_CATALOG="$AV_SKILL/references/policy-catalog.md"
if [[ -f "$AV_CATALOG" ]]; then
  for domain in "Universal Policies" "Financial Domain" "E-Commerce Domain" "Healthcare Domain" "General Domain"; do
    # Match the H2 heading with a prefix — parenthetical suffixes are fine.
    if grep -q "^## ${domain}" "$AV_CATALOG"; then
      pass "policy-catalog has '${domain}' section"
    else
      fail "policy-catalog has '${domain}' section"
    fi
  done
  # Gate contract sentinel: the SKILL.md must still say criticalPolicyViolations == 0.
  if grep -q "criticalPolicyViolations == 0" "$AV_SKILL/SKILL.md"; then
    pass "architecture-validator gate contract is criticalPolicyViolations == 0"
  else
    fail "architecture-validator gate contract is criticalPolicyViolations == 0"
  fi
fi

# component-test-writer (S2-05) sidecar + AAA contract guards.
CTW_SKILL="$SKILLS_DIR/component-test-writer"
[[ -f "$CTW_SKILL/SKILL.md" ]] && pass "component-test-writer SKILL.md present" \
  || fail "component-test-writer SKILL.md present"
[[ -f "$CTW_SKILL/references/test-patterns.md" ]] \
  && pass "component-test-writer test-patterns.md present" \
  || fail "component-test-writer test-patterns.md present"
[[ -f "$CTW_SKILL/references/framework-recipes.md" ]] \
  && pass "component-test-writer framework-recipes.md present" \
  || fail "component-test-writer framework-recipes.md present"

# AAA contract sentinel: the SKILL.md must still enforce the three-section
# shape. Future edits that delete this line silently degrade the output.
if grep -q "Arrange-Act-Assert" "$CTW_SKILL/SKILL.md"; then
  pass "component-test-writer enforces Arrange-Act-Assert"
else
  fail "component-test-writer enforces Arrange-Act-Assert"
fi

# framework-recipes must cover both vitest and jest — dropping one is how
# detection silently starts guessing in production.
if grep -q "^## vitest$" "$CTW_SKILL/references/framework-recipes.md"; then
  pass "framework-recipes has vitest section"
else
  fail "framework-recipes has vitest section"
fi
if grep -q "^## jest$" "$CTW_SKILL/references/framework-recipes.md"; then
  pass "framework-recipes has jest section"
else
  fail "framework-recipes has jest section"
fi

# @generated banner convention — regeneration safety lives here. If the
# banner string ever drifts, regeneration will clobber human-owned code.
if grep -q "@generated-by vibeflow:component-test-writer" "$CTW_SKILL/SKILL.md"; then
  pass "component-test-writer declares @generated banner"
else
  fail "component-test-writer declares @generated banner"
fi

# contract-test-writer (S2-06) sidecar + gate contract guards.
CONTRACT_SKILL="$SKILLS_DIR/contract-test-writer"
[[ -f "$CONTRACT_SKILL/SKILL.md" ]] && pass "contract-test-writer SKILL.md present" \
  || fail "contract-test-writer SKILL.md present"
[[ -f "$CONTRACT_SKILL/references/breaking-change-rules.md" ]] \
  && pass "contract-test-writer breaking-change-rules.md present" \
  || fail "contract-test-writer breaking-change-rules.md present"
[[ -f "$CONTRACT_SKILL/references/spec-parsers.md" ]] \
  && pass "contract-test-writer spec-parsers.md present" \
  || fail "contract-test-writer spec-parsers.md present"

# Gate contract sentinel: MAJOR diffs block the release.
if grep -q "MAJOR breaking changes block the release" "$CONTRACT_SKILL/SKILL.md"; then
  pass "contract-test-writer gate: MAJOR blocks release"
else
  fail "contract-test-writer gate: MAJOR blocks release"
fi

# breaking-change-rules.md must declare tables for operation, request,
# response, and header/parameter diffs — dropping a table means a whole
# class of diffs starts classifying as "unknown".
BCR="$CONTRACT_SKILL/references/breaking-change-rules.md"
if [[ -f "$BCR" ]]; then
  for section in "Operation-level diffs" "Request-schema diffs" "Response-schema diffs" "Header + parameter diffs"; do
    if grep -q "^## ${section}" "$BCR"; then
      pass "breaking-change-rules has '${section}' section"
    else
      fail "breaking-change-rules has '${section}' section"
    fi
  done
  # At least one MAJOR rule must exist per table — if all rules are
  # MINOR/PATCH the gate becomes meaningless.
  MAJOR_COUNT="$(grep -c 'MAJOR' "$BCR")"
  if (( MAJOR_COUNT >= 10 )); then
    pass "breaking-change-rules has at least 10 MAJOR rules"
  else
    fail "breaking-change-rules has at least 10 MAJOR rules (got $MAJOR_COUNT)"
  fi
fi

# spec-parsers.md must cover both OpenAPI and GraphQL SDL — the skill's
# Step 1 detection depends on having both sections documented.
SPARSERS="$CONTRACT_SKILL/references/spec-parsers.md"
if [[ -f "$SPARSERS" ]]; then
  if grep -q "^## OpenAPI 3.x" "$SPARSERS"; then
    pass "spec-parsers covers OpenAPI 3.x"
  else
    fail "spec-parsers covers OpenAPI 3.x"
  fi
  if grep -q "^## GraphQL SDL" "$SPARSERS"; then
    pass "spec-parsers covers GraphQL SDL"
  else
    fail "spec-parsers covers GraphQL SDL"
  fi
fi

# business-rule-validator (S2-07) sidecar + gap-taxonomy guards.
BR_SKILL="$SKILLS_DIR/business-rule-validator"
[[ -f "$BR_SKILL/SKILL.md" ]] && pass "business-rule-validator SKILL.md present" \
  || fail "business-rule-validator SKILL.md present"
[[ -f "$BR_SKILL/references/rule-extraction.md" ]] \
  && pass "business-rule-validator rule-extraction.md present" \
  || fail "business-rule-validator rule-extraction.md present"
[[ -f "$BR_SKILL/references/gap-taxonomy.md" ]] \
  && pass "business-rule-validator gap-taxonomy.md present" \
  || fail "business-rule-validator gap-taxonomy.md present"

# Gate contract sentinel: zero uncovered P0 + zero contradicted.
if grep -q "zero uncovered P0 rules and zero contradicted rules" "$BR_SKILL/SKILL.md"; then
  pass "business-rule-validator gate: zero uncovered P0 + zero contradicted"
else
  fail "business-rule-validator gate: zero uncovered P0 + zero contradicted"
fi

# rule-extraction.md must cover all 4 tiers — pattern drift here means
# the extractor silently stops finding rules.
RE="$BR_SKILL/references/rule-extraction.md"
if [[ -f "$RE" ]]; then
  for tier in "Tier 1 — RFC 2119 keywords" "Tier 2 — Conditional imperatives" "Tier 3 — Prohibition verbs" "Tier 4 — Domain trigger phrases"; do
    if grep -q "^### ${tier}" "$RE"; then
      pass "rule-extraction has '${tier}'"
    else
      fail "rule-extraction has '${tier}'"
    fi
  done
fi

# gap-taxonomy.md catalog size sentinel — shrinking the taxonomy means
# the skill starts emitting "unknown gap" classifications in production.
GT="$BR_SKILL/references/gap-taxonomy.md"
if [[ -f "$GT" ]]; then
  GAP_COUNT="$(grep -c '^### GAP-' "$GT")"
  if (( GAP_COUNT >= 10 )); then
    pass "gap-taxonomy has at least 10 gap categories (got $GAP_COUNT)"
  else
    fail "gap-taxonomy has at least 10 gap categories (got $GAP_COUNT)"
  fi
fi

# test-data-manager (S2-08) sidecar + determinism guards.
TDM_SKILL="$SKILLS_DIR/test-data-manager"
[[ -f "$TDM_SKILL/SKILL.md" ]] && pass "test-data-manager SKILL.md present" \
  || fail "test-data-manager SKILL.md present"
[[ -f "$TDM_SKILL/references/generator-patterns.md" ]] \
  && pass "test-data-manager generator-patterns.md present" \
  || fail "test-data-manager generator-patterns.md present"
[[ -f "$TDM_SKILL/references/edge-case-catalog.md" ]] \
  && pass "test-data-manager edge-case-catalog.md present" \
  || fail "test-data-manager edge-case-catalog.md present"

# Determinism contract sentinel — same seed → same output. This is THE
# non-negotiable invariant of this skill.
if grep -q "Same seed → same output" "$TDM_SKILL/SKILL.md"; then
  pass "test-data-manager declares determinism contract"
else
  fail "test-data-manager declares determinism contract"
fi

# generator-patterns must embed mulberry32 verbatim — the skill copies
# from the @generated-start block into every factory. Dropping it means
# every generated factory picks a different PRNG implementation.
GP="$TDM_SKILL/references/generator-patterns.md"
if [[ -f "$GP" ]]; then
  if grep -q "mulberry32" "$GP"; then
    pass "generator-patterns embeds mulberry32 PRNG"
  else
    fail "generator-patterns embeds mulberry32 PRNG"
  fi
  # Forbid Math.random / Date.now in the reference file — any slip
  # there propagates into every generated factory.
  if grep -qE '(Math\.random|Date\.now)\s*\(\s*\)[^"`]' "$GP"; then
    # Block only if the match is on a code line, not a prose mention.
    # Prose is fine; bare call syntax is not. Relax: allow forbidden
    # mentions as long as they're prefixed with "never use" / "forbidden".
    if grep -qE '(never use|forbidden|MUST NOT|DO NOT).*(Math\.random|Date\.now)' "$GP"; then
      pass "generator-patterns rejects Math.random/Date.now"
    else
      fail "generator-patterns rejects Math.random/Date.now (bare call detected)"
    fi
  else
    pass "generator-patterns rejects Math.random/Date.now"
  fi
fi

# edge-case-catalog must cover the core primitive groups. Shrinking any
# group means the skill emits "pending:" comments for that whole type.
EC="$TDM_SKILL/references/edge-case-catalog.md"
if [[ -f "$EC" ]]; then
  for group in "Strings" "Numbers" "Booleans" "Dates" "Arrays" "Objects / optional / nullable"; do
    if grep -q "^## ${group}" "$EC"; then
      pass "edge-case-catalog has '${group}' section"
    else
      fail "edge-case-catalog has '${group}' section"
    fi
  done
  # Every EC-XXX-NNN id is cited in the skill at runtime; the catalog
  # needs enough entries per primitive to be actually useful.
  EC_COUNT="$(grep -c '^### EC-' "$EC")"
  if (( EC_COUNT >= 25 )); then
    pass "edge-case-catalog has at least 25 entries (got $EC_COUNT)"
  else
    fail "edge-case-catalog has at least 25 entries (got $EC_COUNT)"
  fi
fi

# invariant-formalizer (S2-09) sidecar + taxonomy + recipe guards.
IF_SKILL="$SKILLS_DIR/invariant-formalizer"
[[ -f "$IF_SKILL/SKILL.md" ]] && pass "invariant-formalizer SKILL.md present" \
  || fail "invariant-formalizer SKILL.md present"
[[ -f "$IF_SKILL/references/invariant-taxonomy.md" ]] \
  && pass "invariant-formalizer invariant-taxonomy.md present" \
  || fail "invariant-formalizer invariant-taxonomy.md present"
[[ -f "$IF_SKILL/references/formalization-recipes.md" ]] \
  && pass "invariant-formalizer formalization-recipes.md present" \
  || fail "invariant-formalizer formalization-recipes.md present"

# Gate contract sentinel: zero unformalized P0 + zero cross-check failures.
if grep -q "zero unformalized P0 invariants and zero cross-check" "$IF_SKILL/SKILL.md"; then
  pass "invariant-formalizer gate: zero unformalized P0 + zero cross-check failures"
else
  fail "invariant-formalizer gate: zero unformalized P0 + zero cross-check failures"
fi

# Taxonomy must declare all 7 base classes. Dropping one means a whole
# shape of invariant starts classifying as "unknown" → taxonomy gap.
IT="$IF_SKILL/references/invariant-taxonomy.md"
if [[ -f "$IT" ]]; then
  for class in "INV-RANGE" "INV-EQUALITY" "INV-SUM" "INV-CARDINALITY" "INV-TEMPORAL" "INV-REFERENTIAL" "INV-IMPLICATION"; do
    if grep -q "^### ${class}" "$IT"; then
      pass "invariant-taxonomy has '${class}' base class"
    else
      fail "invariant-taxonomy has '${class}' base class"
    fi
  done
  # Every domain has at least one overlay row — generic "general" is
  # intentionally empty, but financial/e-commerce/healthcare all need
  # their load-bearing overlays.
  for overlay in "INV-FIN-" "INV-ECOM-" "INV-HLTH-"; do
    OVR_COUNT="$(grep -c "^#### ${overlay}" "$IT")"
    if (( OVR_COUNT >= 1 )); then
      pass "invariant-taxonomy has at least one '${overlay}' overlay"
    else
      fail "invariant-taxonomy has at least one '${overlay}' overlay"
    fi
  done
fi

# formalization-recipes must cover every base class × every target format.
# Base classes: 7 (7 headers). Target formats: zod/runtime/smt/pbt declared
# in the format table. Dropping any recipe means the skill silently emits
# unchecked code in that format.
FR="$IF_SKILL/references/formalization-recipes.md"
if [[ -f "$FR" ]]; then
  for class in "INV-RANGE" "INV-EQUALITY" "INV-SUM" "INV-CARDINALITY" "INV-TEMPORAL" "INV-REFERENTIAL" "INV-IMPLICATION"; do
    # Match H2 prefix — parenthetical suffixes are fine.
    if grep -q "^## ${class}" "$FR"; then
      pass "formalization-recipes has '${class}' section"
    else
      fail "formalization-recipes has '${class}' section"
    fi
  done
  for fmt in "zod" "runtime" "smt" "pbt"; do
    if grep -q "^| \`${fmt}\` |" "$FR"; then
      pass "formalization-recipes declares '${fmt}' target format"
    else
      fail "formalization-recipes declares '${fmt}' target format"
    fi
  done
fi

# checklist-generator (S2-10) sidecar + templates/catalog/gate guards.
CG_SKILL="$SKILLS_DIR/checklist-generator"
[[ -f "$CG_SKILL/SKILL.md" ]] && pass "checklist-generator SKILL.md present" \
  || fail "checklist-generator SKILL.md present"
[[ -f "$CG_SKILL/references/checklist-templates.md" ]] \
  && pass "checklist-generator checklist-templates.md present" \
  || fail "checklist-generator checklist-templates.md present"
[[ -f "$CG_SKILL/references/item-catalog.md" ]] \
  && pass "checklist-generator item-catalog.md present" \
  || fail "checklist-generator item-catalog.md present"

# Gate contract sentinel: zero unverifiable items.
if grep -q "zero unverifiable items in the generated checklist" "$CG_SKILL/SKILL.md"; then
  pass "checklist-generator gate: zero unverifiable items"
else
  fail "checklist-generator gate: zero unverifiable items"
fi

# Templates must cover all 4 canonical contexts. Dropping a context
# means the skill silently refuses that whole review flow.
CT="$CG_SKILL/references/checklist-templates.md"
if [[ -f "$CT" ]]; then
  for ctx in "pr-review" "release" "feature" "accessibility"; do
    if grep -q "^## Context: \`${ctx}\`" "$CT"; then
      pass "checklist-templates has '${ctx}' context"
    else
      fail "checklist-templates has '${ctx}' context"
    fi
  done
  # Every domain overlay section must be present (general has no items).
  for domain in "Financial" "E-commerce" "Healthcare"; do
    if grep -q "^### ${domain}$" "$CT"; then
      pass "checklist-templates has '${domain}' domain overlay"
    else
      fail "checklist-templates has '${domain}' domain overlay"
    fi
  done
fi

# item-catalog size sentinel — shrinking the catalog is how templates
# start pointing at missing ids.
IC="$CG_SKILL/references/item-catalog.md"
if [[ -f "$IC" ]]; then
  ITEM_COUNT="$(grep -c '^### CL-' "$IC")"
  if (( ITEM_COUNT >= 40 )); then
    pass "item-catalog has at least 40 items (got $ITEM_COUNT)"
  else
    fail "item-catalog has at least 40 items (got $ITEM_COUNT)"
  fi
fi

# Every template reference must resolve to a real catalog entry. This
# is THE load-bearing consistency check — if templates drift from the
# catalog, the skill refuses to run in production. Check it in CI
# too so the drift is caught at commit time, not invocation time.
if [[ -f "$CT" && -f "$IC" ]]; then
  # Extract every referenced id from templates (lines starting with "- CL-").
  MISSING_REFS=0
  while IFS= read -r ref_id; do
    [[ -z "$ref_id" ]] && continue
    if ! grep -q "^### ${ref_id}$" "$IC"; then
      MISSING_REFS=$((MISSING_REFS + 1))
      echo "    template references missing catalog id: $ref_id"
    fi
  done < <(grep -oE '^- (CL-[A-Z0-9-]+)' "$CT" | sed 's/^- //' | sort -u)
  assert_eq "every template id resolves to a catalog entry" "0" "$MISSING_REFS"
fi

# e2e-test-writer (S3-03) sidecar + flake-contract guards.
E2E_SKILL="$SKILLS_DIR/e2e-test-writer"
[[ -f "$E2E_SKILL/SKILL.md" ]] && pass "e2e-test-writer SKILL.md present" \
  || fail "e2e-test-writer SKILL.md present"
[[ -f "$E2E_SKILL/references/platform-recipes.md" ]] \
  && pass "e2e-test-writer platform-recipes.md present" \
  || fail "e2e-test-writer platform-recipes.md present"
[[ -f "$E2E_SKILL/references/pom-patterns.md" ]] \
  && pass "e2e-test-writer pom-patterns.md present" \
  || fail "e2e-test-writer pom-patterns.md present"

# Gate contract sentinel — the three-rule flake contract is the whole
# point of this skill. Silently weakening it is how flake returns.
if grep -q "zero raw selectors in the test body, zero sleep-based waits, zero xpath selectors" "$E2E_SKILL/SKILL.md"; then
  pass "e2e-test-writer gate: zero raw selectors + zero sleeps + zero xpath"
else
  fail "e2e-test-writer gate: zero raw selectors + zero sleeps + zero xpath"
fi

# platform-recipes must cover Playwright (web) AND Detox (mobile). A
# dropped section means the skill silently degrades to the other
# platform.
PR="$E2E_SKILL/references/platform-recipes.md"
if [[ -f "$PR" ]]; then
  if grep -q "^## Web — Playwright" "$PR"; then
    pass "platform-recipes has 'Web — Playwright' section"
  else
    fail "platform-recipes has 'Web — Playwright' section"
  fi
  if grep -q "^## Mobile — Detox" "$PR"; then
    pass "platform-recipes has 'Mobile — Detox' section"
  else
    fail "platform-recipes has 'Mobile — Detox' section"
  fi
  # Forbid-list sentinel: Playwright's waitForTimeout must be called out
  # as forbidden, not allowed. A regression here is how "just add a
  # wait" starts creeping back into generated tests.
  if grep -q "waitForTimeout" "$PR" && grep -qE "(❌|forbidden|Forbidden).*waitForTimeout|waitForTimeout.*forbidden" "$PR"; then
    pass "platform-recipes marks waitForTimeout as forbidden"
  else
    fail "platform-recipes marks waitForTimeout as forbidden"
  fi
fi

# pom-patterns must declare the 4 auth strategies — dropping one is how
# "accidentally authenticated as the wrong user" bugs ship.
POM="$E2E_SKILL/references/pom-patterns.md"
if [[ -f "$POM" ]]; then
  for strategy in "anonymous" "stored-session" "token-injection" "ui-login"; do
    if grep -q "^### Strategy \`${strategy}\`" "$POM"; then
      pass "pom-patterns declares '${strategy}' auth strategy"
    else
      fail "pom-patterns declares '${strategy}' auth strategy"
    fi
  done
  # Selector stability policy sentinel — xpath must be marked rejected
  # (not merely "discouraged"). Relaxing this is the skill's single
  # biggest long-term risk.
  if grep -q "xpath" "$POM" && grep -iqE "(rejected|banned|forbidden).*xpath|xpath.*(rejected|banned|forbidden)" "$POM"; then
    pass "pom-patterns marks xpath as rejected/banned"
  else
    fail "pom-patterns marks xpath as rejected/banned"
  fi
fi

# @generated banner reuse — e2e-test-writer mirrors the same regeneration
# convention as component-test-writer so human-edited regions survive.
if grep -q "@generated-by vibeflow:e2e-test-writer" "$E2E_SKILL/SKILL.md"; then
  pass "e2e-test-writer declares @generated banner"
else
  fail "e2e-test-writer declares @generated banner"
fi

# uat-executor (S3-04) sidecar + evidence/production/halt guards.
UAT_SKILL="$SKILLS_DIR/uat-executor"
[[ -f "$UAT_SKILL/SKILL.md" ]] && pass "uat-executor SKILL.md present" \
  || fail "uat-executor SKILL.md present"
[[ -f "$UAT_SKILL/references/execution-protocol.md" ]] \
  && pass "uat-executor execution-protocol.md present" \
  || fail "uat-executor execution-protocol.md present"
[[ -f "$UAT_SKILL/references/report-schema.md" ]] \
  && pass "uat-executor report-schema.md present" \
  || fail "uat-executor report-schema.md present"

# Gate contract sentinel — three invariants for downstream trust.
# Match the distinctive chunk; avoid the backticked word "passed" that
# bash grep+quoting mangles.
if grep -q "Every failed step carries evidence, every P0 scenario is executed" "$UAT_SKILL/SKILL.md" \
   && grep -q "without a recorded assertion" "$UAT_SKILL/SKILL.md"; then
  pass "uat-executor gate: evidence + P0 + no synthetic passes"
else
  fail "uat-executor gate: evidence + P0 + no synthetic passes"
fi

# Production guard sentinel — "no override flag" is the load-bearing
# phrase. Relaxing it is how "just this once" becomes a PagerDuty story.
if grep -q "Does NOT run against production. There is no override flag" "$UAT_SKILL/SKILL.md"; then
  pass "uat-executor forbids production runs with no override"
else
  fail "uat-executor forbids production runs with no override"
fi

# Execution protocol must declare all 3 step types. Dropping one leaves
# a whole class of scenarios silently unexecutable.
EP="$UAT_SKILL/references/execution-protocol.md"
if [[ -f "$EP" ]]; then
  for stype in "automated" "human" "probe"; do
    if grep -qE "^### 1\.[123] \`${stype}\`" "$EP"; then
      pass "execution-protocol declares '${stype}' step type"
    else
      fail "execution-protocol declares '${stype}' step type"
    fi
  done
  # Halt mode sentinels — the three modes form a closed set.
  for mode in "criticalFailure" "firstFailure" "never"; do
    if grep -q "\`${mode}\`" "$EP"; then
      pass "execution-protocol declares halt mode '${mode}'"
    else
      fail "execution-protocol declares halt mode '${mode}'"
    fi
  done
  # Forbids silent retries — retries hide flake, not fix it.
  if grep -qE "Silent retries|silent retries" "$EP"; then
    pass "execution-protocol forbids silent retries"
  else
    fail "execution-protocol forbids silent retries"
  fi
fi

# Report schema must declare a version + every downstream consumer.
RS="$UAT_SKILL/references/report-schema.md"
if [[ -f "$RS" ]]; then
  if grep -qE "Current schema version.*1" "$RS"; then
    pass "report-schema declares a current schema version"
  else
    fail "report-schema declares a current schema version"
  fi
  for consumer in "test-result-analyzer" "observability-analyzer" "release-decision-engine" "traceability-engine"; do
    if grep -q "^### ${consumer}$" "$RS"; then
      pass "report-schema declares '${consumer}' consumer contract"
    else
      fail "report-schema declares '${consumer}' consumer contract"
    fi
  done
fi

# regression-test-runner (S3-05) sidecar + gate/scope/baseline guards.
RTR_SKILL="$SKILLS_DIR/regression-test-runner"
[[ -f "$RTR_SKILL/SKILL.md" ]] && pass "regression-test-runner SKILL.md present" \
  || fail "regression-test-runner SKILL.md present"
[[ -f "$RTR_SKILL/references/scope-selection.md" ]] \
  && pass "regression-test-runner scope-selection.md present" \
  || fail "regression-test-runner scope-selection.md present"
[[ -f "$RTR_SKILL/references/baseline-policy.md" ]] \
  && pass "regression-test-runner baseline-policy.md present" \
  || fail "regression-test-runner baseline-policy.md present"

# Gate contract — P0 pass rate must be EXACTLY 100%. Not 95%, not 99%.
# The whole trust model of the baseline hangs on this line.
if grep -q "P0 pass rate must be exactly 100%" "$RTR_SKILL/SKILL.md"; then
  pass "regression-test-runner gate: P0 pass rate exactly 100%"
else
  fail "regression-test-runner gate: P0 pass rate exactly 100%"
fi

# Scope declarations — the three scopes form a closed set.
SS="$RTR_SKILL/references/scope-selection.md"
if [[ -f "$SS" ]]; then
  for scope in "smoke" "full" "incremental"; do
    if grep -qE "^## [0-9]\. \`${scope}\`" "$SS"; then
      pass "scope-selection declares '${scope}' scope"
    else
      fail "scope-selection declares '${scope}' scope"
    fi
  done
  # P0-always-in-smoke rule — drops this and fast feedback silently
  # stops covering the most critical tests.
  if grep -q "Every P0 test regardless of tag" "$SS"; then
    pass "scope-selection enforces 'P0 always in smoke' rule"
  else
    fail "scope-selection enforces 'P0 always in smoke' rule"
  fi
fi

# Baseline policy — the promotion rules are the whole point of this
# skill. Check the non-negotiable phrases.
BP="$RTR_SKILL/references/baseline-policy.md"
if [[ -f "$BP" ]]; then
  # Only PASS promotes. If this ever becomes "PASS or mostly-passing"
  # the baseline starts lying.
  if grep -qE "No other verdict promotes\.|only exact \`PASS\`" "$BP"; then
    pass "baseline-policy enforces 'only PASS promotes'"
  else
    fail "baseline-policy enforces 'only PASS promotes'"
  fi
  # Incremental never promotes — it's too narrow to trust.
  if grep -q "Never promotes the baseline" "$BP"; then
    pass "baseline-policy: incremental scope never promotes"
  else
    fail "baseline-policy: incremental scope never promotes"
  fi
  # Staleness horizon tightening-only rule.
  if grep -q "only TIGHTEN" "$BP"; then
    pass "baseline-policy: staleness override can only tighten"
  else
    fail "baseline-policy: staleness override can only tighten"
  fi
  # P0 never in flakyKnown — flakiness is not forgiveness for P0.
  if grep -q "P0 test is never added to \`flakyKnown\`" "$BP"; then
    pass "baseline-policy: P0 never added to flakyKnown"
  else
    fail "baseline-policy: P0 never added to flakyKnown"
  fi
  if grep -qE "Current version:\s*\*\*1\*\*|schemaVersion.*1" "$BP"; then
    pass "baseline-policy declares a current schema version"
  else
    fail "baseline-policy declares a current schema version"
  fi
fi

# test-priority-engine (S3-06) sidecar + gate/mode/risk guards.
TPE_SKILL="$SKILLS_DIR/test-priority-engine"
[[ -f "$TPE_SKILL/SKILL.md" ]] && pass "test-priority-engine SKILL.md present" \
  || fail "test-priority-engine SKILL.md present"
[[ -f "$TPE_SKILL/references/risk-model.md" ]] \
  && pass "test-priority-engine risk-model.md present" \
  || fail "test-priority-engine risk-model.md present"
[[ -f "$TPE_SKILL/references/mode-budgets.md" ]] \
  && pass "test-priority-engine mode-budgets.md present" \
  || fail "test-priority-engine mode-budgets.md present"

# Gate contract sentinel — every affected P0 test lands in the plan,
# regardless of mode or budget. Relaxing this is how test gaps ship.
if grep -q "Every affected P0 test appears in the plan, regardless of mode or" "$TPE_SKILL/SKILL.md"; then
  pass "test-priority-engine gate: affected P0 always in plan"
else
  fail "test-priority-engine gate: affected P0 always in plan"
fi

# Risk model — 6 components form a closed set. Dropping one is how
# "we used to consider churn" becomes a silent regression.
RM="$TPE_SKILL/references/risk-model.md"
if [[ -f "$RM" ]]; then
  for component in "priorityWeight" "affectednessWeight" "baselineFailWeight" "flakeWeight" "churnWeight" "recencyWeight"; do
    if grep -qE "^### 2\.[1-6] \`${component}\`" "$RM"; then
      pass "risk-model declares '${component}' component"
    else
      fail "risk-model declares '${component}' component"
    fi
  done
  # w_p >= 0.2 floor — lower the priority weight and the whole gate
  # model starts slipping.
  if grep -q "w_p >= 0.2" "$RM"; then
    pass "risk-model enforces w_p >= 0.2 floor"
  else
    fail "risk-model enforces w_p >= 0.2 floor"
  fi
fi

# Mode budgets — the three canonical modes form a closed set; dropping
# one means the skill silently refuses that whole trigger path.
MB="$TPE_SKILL/references/mode-budgets.md"
if [[ -f "$MB" ]]; then
  for mode in "quick" "smart" "full"; do
    if grep -q "^### \`${mode}\`" "$MB"; then
      pass "mode-budgets declares '${mode}' mode"
    else
      fail "mode-budgets declares '${mode}' mode"
    fi
  done
  # Overrides can only TIGHTEN — same pattern as baseline staleness.
  if grep -qE "only TIGHTEN|may only TIGHTEN" "$MB"; then
    pass "mode-budgets: overrides may only tighten"
  else
    fail "mode-budgets: overrides may only tighten"
  fi
  # 10-second floor — protects users from "--time-budget 5" footguns.
  if grep -q "10-second floor" "$MB"; then
    pass "mode-budgets declares 10-second time-budget floor"
  else
    fail "mode-budgets declares 10-second time-budget floor"
  fi
fi

# mutation-test-runner (S3-07) sidecar + gate/catalog/threshold guards.
MTR_SKILL="$SKILLS_DIR/mutation-test-runner"
[[ -f "$MTR_SKILL/SKILL.md" ]] && pass "mutation-test-runner SKILL.md present" \
  || fail "mutation-test-runner SKILL.md present"
[[ -f "$MTR_SKILL/references/mutation-operators.md" ]] \
  && pass "mutation-test-runner mutation-operators.md present" \
  || fail "mutation-test-runner mutation-operators.md present"
[[ -f "$MTR_SKILL/references/score-thresholds.md" ]] \
  && pass "mutation-test-runner score-thresholds.md present" \
  || fail "mutation-test-runner score-thresholds.md present"

# Gate contract sentinel — P0 zero-survivor + domain threshold. The
# two-rule gate is the skill's whole reason to exist.
if grep -q "Zero surviving mutants in P0 code AND mutation score meets the" "$MTR_SKILL/SKILL.md"; then
  pass "mutation-test-runner gate: P0 zero-survivor + threshold"
else
  fail "mutation-test-runner gate: P0 zero-survivor + threshold"
fi

# Mutation operator categories — 5 categories form a closed set. If a
# category is silently dropped, a whole class of bugs stops being
# measured.
MO="$MTR_SKILL/references/mutation-operators.md"
if [[ -f "$MO" ]]; then
  for category in "Arithmetic operators" "Conditional / boundary operators" "Literal + value operators" "Removal + replacement operators" "Exception + promise operators"; do
    if grep -q "^## [0-9]\. ${category}" "$MO"; then
      pass "mutation-operators has '${category}' category"
    else
      fail "mutation-operators has '${category}' category"
    fi
  done
  # A minimum of 15 operators keeps the catalog bench above a noise
  # floor. The current catalog has ~17.
  OP_COUNT="$(grep -c "^### [A-Z][A-Z0-9_]*$" "$MO")"
  if (( OP_COUNT >= 15 )); then
    pass "mutation-operators has at least 15 operators (got $OP_COUNT)"
  else
    fail "mutation-operators has at least 15 operators (got $OP_COUNT)"
  fi
fi

# Score thresholds — the four domains each need a threshold row. A
# domain dropping out of the table is how a project silently
# inherits the lowest threshold.
ST="$MTR_SKILL/references/score-thresholds.md"
if [[ -f "$ST" ]]; then
  for domain in "financial" "healthcare" "e-commerce" "general"; do
    if grep -qE "^\| \`${domain}\` \|" "$ST"; then
      pass "score-thresholds declares '${domain}' domain threshold"
    else
      fail "score-thresholds declares '${domain}' domain threshold"
    fi
  done
  # Override-can-only-TIGHTEN rule — same pattern as the other
  # skills' override disciplines.
  if grep -qE "only TIGHTEN|can only TIGHTEN" "$ST"; then
    pass "score-thresholds: overrides may only tighten"
  else
    fail "score-thresholds: overrides may only tighten"
  fi
  # no-coverage → survived rule — the most important design choice
  # in the scoring scheme. Flipping it silently would let bad suites
  # score perfectly.
  if grep -q "no-coverage.*counts as SURVIVED\|noCoverage.*counts as survived\|classifies as \`survived\`" "$ST"; then
    pass "score-thresholds declares 'no-coverage counts as survived'"
  else
    fail "score-thresholds declares 'no-coverage counts as survived'"
  fi
fi

# environment-orchestrator (S3-08) sidecar + recipe integrity guards.
EO_SKILL="$SKILLS_DIR/environment-orchestrator"
[[ -f "$EO_SKILL/SKILL.md" ]] && pass "environment-orchestrator SKILL.md present" \
  || fail "environment-orchestrator SKILL.md present"
[[ -f "$EO_SKILL/references/environment-profiles.md" ]] \
  && pass "environment-orchestrator environment-profiles.md present" \
  || fail "environment-orchestrator environment-profiles.md present"
[[ -f "$EO_SKILL/references/component-catalog.md" ]] \
  && pass "environment-orchestrator component-catalog.md present" \
  || fail "environment-orchestrator component-catalog.md present"

# Gate contract sentinel — healthcheck + teardown + secrets-by-reference.
# Three non-negotiables that keep environments reproducible AND clean.
if grep -q "Every component has a healthcheck, every setup has a teardown" "$EO_SKILL/SKILL.md"; then
  pass "environment-orchestrator gate: healthcheck + teardown + secrets-by-ref"
else
  fail "environment-orchestrator gate: healthcheck + teardown + secrets-by-ref"
fi

# Production guard — same rule as uat-executor. No override flag.
if grep -q "no override flag" "$EO_SKILL/SKILL.md" || grep -q "No override flag" "$EO_SKILL/SKILL.md"; then
  pass "environment-orchestrator declares no-override production rule"
else
  fail "environment-orchestrator declares no-override production rule"
fi

# Profile catalog — 5 profiles form a closed set. Dropping one means the
# skill silently has no recipe for a whole test type.
EP="$EO_SKILL/references/environment-profiles.md"
if [[ -f "$EP" ]]; then
  for profile in "unit" "integration" "e2e" "uat" "perf"; do
    if grep -qE "^## [0-9]\. \`${profile}\`" "$EP"; then
      pass "environment-profiles declares '${profile}' profile"
    else
      fail "environment-profiles declares '${profile}' profile"
    fi
  done
  # Applicability matrix section — drift here is how combos get silently
  # allowed that shouldn't exist.
  if grep -q "applicability matrix" "$EP" || grep -q "Profile applicability matrix" "$EP"; then
    pass "environment-profiles has applicability matrix"
  else
    fail "environment-profiles has applicability matrix"
  fi
fi

# Component catalog — count floor + `latest` ban. A catalog that drops
# below 10 entries usually means a section got deleted by accident.
CC="$EO_SKILL/references/component-catalog.md"
if [[ -f "$CC" ]]; then
  # Count bolded component headers (### <name>).
  COMP_COUNT="$(grep -cE "^### [a-z][a-z0-9-]+$" "$CC")"
  if (( COMP_COUNT >= 10 )); then
    pass "component-catalog has at least 10 components (got $COMP_COUNT)"
  else
    fail "component-catalog has at least 10 components (got $COMP_COUNT)"
  fi
  # `latest` ban — the whole trust model depends on pinned images.
  # The document itself can SAY the word "latest" but no `- **image**:`
  # field may end in `:latest` without a digest. Scan for image rows.
  if grep -qE "^- \*\*image\*\*: \`[^\`]*:latest\`" "$CC"; then
    fail "component-catalog forbids :latest image tags"
  else
    pass "component-catalog forbids :latest image tags"
  fi
  # Digest discipline — every entry must have a sha256 digest.
  ENTRIES_WITH_DIGEST="$(grep -cE '^- \*\*image\*\*:.*@sha256:' "$CC")"
  if (( ENTRIES_WITH_DIGEST >= 10 )); then
    pass "component-catalog has digests on ≥10 components (got $ENTRIES_WITH_DIGEST)"
  else
    fail "component-catalog has digests on ≥10 components (got $ENTRIES_WITH_DIGEST)"
  fi
fi

# chaos-injector (S3-09) sidecar + safety/profile guards.
CI_CHAOS="$SKILLS_DIR/chaos-injector"
[[ -f "$CI_CHAOS/SKILL.md" ]] && pass "chaos-injector SKILL.md present" \
  || fail "chaos-injector SKILL.md present"
[[ -f "$CI_CHAOS/references/chaos-catalog.md" ]] \
  && pass "chaos-injector chaos-catalog.md present" \
  || fail "chaos-injector chaos-catalog.md present"
[[ -f "$CI_CHAOS/references/scoring-rubric.md" ]] \
  && pass "chaos-injector scoring-rubric.md present" \
  || fail "chaos-injector scoring-rubric.md present"

# Gate contract sentinel — the three invariants: never production,
# verified recovery, no gentle cascades. Relaxing any of these is how
# chaos injection turns into outage injection.
if grep -q "Never against production" "$CI_CHAOS/SKILL.md" \
   && grep -q "Every injection has a verified recovery" "$CI_CHAOS/SKILL.md" \
   && grep -q "No cascading failures on the gentle profile" "$CI_CHAOS/SKILL.md"; then
  pass "chaos-injector gate: never prod + verified recovery + no gentle cascade"
else
  fail "chaos-injector gate: never prod + verified recovery + no gentle cascade"
fi

# Production guard — same no-override rule as uat-executor and
# environment-orchestrator. This is the single most important
# invariant in the whole skill.
if grep -q "No override flag" "$CI_CHAOS/SKILL.md" || grep -q "no override flag" "$CI_CHAOS/SKILL.md"; then
  pass "chaos-injector declares no-override production rule"
else
  fail "chaos-injector declares no-override production rule"
fi

# Chaos catalog — 4 categories form a closed set. Dropping one is how
# a whole class of failures stops being testable.
CAT="$CI_CHAOS/references/chaos-catalog.md"
if [[ -f "$CAT" ]]; then
  for category in "Network — latency injection" "Network — connection loss" "Dependency — service unavailability" "Clock — time skew" "Resource — exhaustion"; do
    if grep -qE "^## [0-9]\. ${category}" "$CAT"; then
      pass "chaos-catalog has '${category}' category"
    else
      fail "chaos-catalog has '${category}' category"
    fi
  done
  # Entry count floor — a catalog below 10 entries usually means a
  # section got deleted.
  ENTRY_COUNT="$(grep -cE '^### [a-z][a-z0-9-]+$' "$CAT")"
  if (( ENTRY_COUNT >= 10 )); then
    pass "chaos-catalog has at least 10 entries (got $ENTRY_COUNT)"
  else
    fail "chaos-catalog has at least 10 entries (got $ENTRY_COUNT)"
  fi
  # No parallel chaos — the serial policy is the skill's single most
  # important safety property.
  if grep -q "No parallel chaos" "$CAT"; then
    pass "chaos-catalog enforces 'No parallel chaos' rule"
  else
    fail "chaos-catalog enforces 'No parallel chaos' rule"
  fi
fi

# Scoring rubric — 3 profiles with exact thresholds, 4 components with
# floor on w_r.
SR="$CI_CHAOS/references/scoring-rubric.md"
if [[ -f "$SR" ]]; then
  for profile in "gentle" "moderate" "brutal"; do
    if grep -q "\`${profile}\`" "$SR"; then
      pass "scoring-rubric declares '${profile}' profile"
    else
      fail "scoring-rubric declares '${profile}' profile"
    fi
  done
  # Gentle must have the highest bar — if the default ever flips this,
  # the whole gentle-profile safety story collapses.
  if grep -qE "\`gentle\`.*\*\*85 / 100\*\*" "$SR" || grep -qE "gentle.*85 / 100" "$SR"; then
    pass "scoring-rubric: gentle threshold is 85/100"
  else
    fail "scoring-rubric: gentle threshold is 85/100"
  fi
  # w_r floor — recovery is the primary signal.
  if grep -q "w_r >= 0.25" "$SR"; then
    pass "scoring-rubric enforces w_r >= 0.25 floor"
  else
    fail "scoring-rubric enforces w_r >= 0.25 floor"
  fi
fi

# cross-run-consistency (S3-10) sidecar + gate/taxonomy/mode guards.
CRC_SKILL="$SKILLS_DIR/cross-run-consistency"
[[ -f "$CRC_SKILL/SKILL.md" ]] && pass "cross-run-consistency SKILL.md present" \
  || fail "cross-run-consistency SKILL.md present"
[[ -f "$CRC_SKILL/references/non-determinism-taxonomy.md" ]] \
  && pass "cross-run-consistency non-determinism-taxonomy.md present" \
  || fail "cross-run-consistency non-determinism-taxonomy.md present"
[[ -f "$CRC_SKILL/references/tolerance-modes.md" ]] \
  && pass "cross-run-consistency tolerance-modes.md present" \
  || fail "cross-run-consistency tolerance-modes.md present"

# Gate contract sentinel — P0 must be strict-consistent, no override.
if grep -q "P0 scenarios must be strict-consistent" "$CRC_SKILL/SKILL.md"; then
  pass "cross-run-consistency gate: P0 strict-consistent"
else
  fail "cross-run-consistency gate: P0 strict-consistent"
fi

# Domain threshold sentinel — financial/healthcare 0.98, general 0.90
# floors. Sliding this weakens non-P0 signals silently.
if grep -qE "financial.*0\.98" "$CRC_SKILL/references/tolerance-modes.md" \
   && grep -qE "general.*0\.90" "$CRC_SKILL/references/tolerance-modes.md"; then
  pass "tolerance-modes declares domain thresholds"
else
  fail "tolerance-modes declares domain thresholds"
fi

# Non-determinism taxonomy — 6 classes form a closed set. Dropping one
# means a whole root-cause family gets silently re-bucketed into UNKNOWN.
NDT="$CRC_SKILL/references/non-determinism-taxonomy.md"
if [[ -f "$NDT" ]]; then
  for class in "TIMING" "ORDERING" "SEED-DRIFT" "EXTERNAL-STATE" "RESOURCE-CONTENTION" "UNKNOWN"; do
    if grep -qE "^## [0-9]\. \`${class}\`" "$NDT"; then
      pass "non-determinism-taxonomy declares '${class}' class"
    else
      fail "non-determinism-taxonomy declares '${class}' class"
    fi
  done
  # Walk order sentinel — classification is deterministic because the
  # walk order is fixed. Silent reorder is how "probably TIMING" starts
  # getting classified as EXTERNAL-STATE.
  if grep -q "Walk order" "$NDT" || grep -q "walk order" "$NDT"; then
    pass "non-determinism-taxonomy declares walk order"
  else
    fail "non-determinism-taxonomy declares walk order"
  fi
fi

# Tolerance modes — strict vs tolerant, runtime override rule.
TM="$CRC_SKILL/references/tolerance-modes.md"
if [[ -f "$TM" ]]; then
  if grep -qE "^### \`strict\`" "$TM"; then
    pass "tolerance-modes declares 'strict' mode"
  else
    fail "tolerance-modes declares 'strict' mode"
  fi
  if grep -qE "^### \`tolerant\`" "$TM"; then
    pass "tolerance-modes declares 'tolerant' mode"
  else
    fail "tolerance-modes declares 'tolerant' mode"
  fi
  # P0 never in tolerant — structural rule for the whole skill.
  # Match the "P0 test is a config error" phrasing in §1 of the file.
  if grep -q "P0 test is a config error the skill refuses to execute" "$TM"; then
    pass "tolerance-modes: P0 never accepts tolerant mode"
  else
    fail "tolerance-modes: P0 never accepts tolerant mode"
  fi
  # --mode tolerant runtime flag REJECTED — operator mistake guard.
  if grep -qE "\`--mode tolerant\` runtime flag is REJECTED|--mode tolerant\` runtime flag is REJECTED" "$TM"; then
    pass "tolerance-modes rejects --mode tolerant runtime flag"
  else
    fail "tolerance-modes rejects --mode tolerant runtime flag"
  fi
fi

# test-result-analyzer (S3-11) sidecar + classification + ticket guards.
TRA_SKILL="$SKILLS_DIR/test-result-analyzer"
[[ -f "$TRA_SKILL/SKILL.md" ]] && pass "test-result-analyzer SKILL.md present" \
  || fail "test-result-analyzer SKILL.md present"
[[ -f "$TRA_SKILL/references/failure-taxonomy.md" ]] \
  && pass "test-result-analyzer failure-taxonomy.md present" \
  || fail "test-result-analyzer failure-taxonomy.md present"
[[ -f "$TRA_SKILL/references/ticket-template.md" ]] \
  && pass "test-result-analyzer ticket-template.md present" \
  || fail "test-result-analyzer ticket-template.md present"

# Gate contract: no UNCLASSIFIED leaks + BUG confidence ≥ 0.7 + ticket
# traceability required. All three are load-bearing for downstream.
if grep -q "No \`UNCLASSIFIED\` leaks to downstream" "$TRA_SKILL/SKILL.md" \
   && grep -q "Every \`BUG\` classification has \`confidence >= 0.7\`" "$TRA_SKILL/SKILL.md" \
   && grep -q "Every generated ticket traces back to a scenario id" "$TRA_SKILL/SKILL.md"; then
  pass "test-result-analyzer gate: unclassified + confidence + traceability"
else
  fail "test-result-analyzer gate: unclassified + confidence + traceability"
fi

# Failure taxonomy — 5 classes form a closed set. Dropping one silently
# misclassifies a whole failure mode.
FT="$TRA_SKILL/references/failure-taxonomy.md"
if [[ -f "$FT" ]]; then
  for class in "FLAKY" "ENVIRONMENT" "TEST-DEFECT" "BUG" "UNCLASSIFIED"; do
    if grep -qE "^## [0-9]\. \`${class}\`" "$FT"; then
      pass "failure-taxonomy declares '${class}' class"
    else
      fail "failure-taxonomy declares '${class}' class"
    fi
  done
  # Walk order sentinel — classification is deterministic because the
  # walk order is fixed. Silent reorder is how "BUG-first" breaks the
  # "flaky takes priority" trust.
  if grep -q "Walk order" "$FT" || grep -q "walk order" "$FT"; then
    pass "failure-taxonomy declares walk order"
  else
    fail "failure-taxonomy declares walk order"
  fi
  # BUG-fourth-not-first rule — structural. Silently promoting BUG to
  # earlier in the walk is how tickets start getting mass-generated for
  # flakes and environment issues.
  if grep -q "Why BUG is fourth, not first" "$FT"; then
    pass "failure-taxonomy enforces 'BUG is fourth' rule"
  else
    fail "failure-taxonomy enforces 'BUG is fourth' rule"
  fi
fi

# Ticket template — schema version + dedupKey rule + no-ticket conditions.
TT="$TRA_SKILL/references/ticket-template.md"
if [[ -f "$TT" ]]; then
  if grep -q "schema version: 1" "$TT" || grep -q "ticket schema version: 1" "$TT"; then
    pass "ticket-template declares current schema version"
  else
    fail "ticket-template declares current schema version"
  fi
  if grep -q "dedupKey" "$TT"; then
    pass "ticket-template declares dedupKey field"
  else
    fail "ticket-template declares dedupKey field"
  fi
  # Confidence floor enforced in the no-ticket list.
  if grep -q "confidence < 0.7" "$TT"; then
    pass "ticket-template enforces confidence ≥ 0.7 floor"
  else
    fail "ticket-template enforces confidence ≥ 0.7 floor"
  fi
  # History append-only rule — tickets never edit, only append.
  if grep -q "append-only" "$TT"; then
    pass "ticket-template enforces append-only history"
  else
    fail "ticket-template enforces append-only history"
  fi
fi

# coverage-analyzer (S3-12) sidecar + gate/metrics/gap guards.
COV_SKILL="$SKILLS_DIR/coverage-analyzer"
[[ -f "$COV_SKILL/SKILL.md" ]] && pass "coverage-analyzer SKILL.md present" \
  || fail "coverage-analyzer SKILL.md present"
[[ -f "$COV_SKILL/references/coverage-metrics.md" ]] \
  && pass "coverage-analyzer coverage-metrics.md present" \
  || fail "coverage-analyzer coverage-metrics.md present"
[[ -f "$COV_SKILL/references/gap-prioritization.md" ]] \
  && pass "coverage-analyzer gap-prioritization.md present" \
  || fail "coverage-analyzer gap-prioritization.md present"

# Gate contract — P0 zero-uncovered + domain threshold + no critical-
# path exclusions. Three-rule compose.
if grep -q "Zero uncovered lines or branches in P0 code" "$COV_SKILL/SKILL.md" \
   && grep -q "overall coverage" "$COV_SKILL/SKILL.md" \
   && grep -q "no exclusions on critical paths" "$COV_SKILL/SKILL.md"; then
  pass "coverage-analyzer gate: P0 + threshold + no critical exclusions"
else
  fail "coverage-analyzer gate: P0 + threshold + no critical exclusions"
fi

# Coverage metrics — 4 domain threshold rows. Sliding any of these
# silently weakens the whole gate.
CM="$COV_SKILL/references/coverage-metrics.md"
if [[ -f "$CM" ]]; then
  for domain in "financial" "healthcare" "e-commerce" "general"; do
    if grep -qE "^\| \`${domain}\` \|" "$CM"; then
      pass "coverage-metrics declares '${domain}' domain row"
    else
      fail "coverage-metrics declares '${domain}' domain row"
    fi
  done
  # Summation-not-averaging rule — the load-bearing rollup decision.
  if grep -q "NOT average of per-file" "$CM" || grep -q "sum numerators and denominators" "$CM"; then
    pass "coverage-metrics enforces sum-over-average rollup"
  else
    fail "coverage-metrics enforces sum-over-average rollup"
  fi
  # Critical-path exclusion forbidden rule — structural, non-negotiable.
  if grep -q "criticalPaths file excluded ANYWHERE" "$CM" || grep -q "critical-path exclusion" "$CM"; then
    pass "coverage-metrics forbids critical-path exclusions"
  else
    fail "coverage-metrics forbids critical-path exclusions"
  fi
  # null ≠ 0 rule — a file with no branches isn't "perfect branch coverage".
  if grep -qE "NOT zero|\`null\`, NOT zero" "$CM"; then
    pass "coverage-metrics: null != zero for empty denominators"
  else
    fail "coverage-metrics: null != zero for empty denominators"
  fi
fi

# Gap prioritization — 4 components form a closed set + w_p floor.
GP="$COV_SKILL/references/gap-prioritization.md"
if [[ -f "$GP" ]]; then
  for component in "priorityComponent" "criticalityComponent" "churnComponent" "requirementLinkComponent"; do
    if grep -qE "^### 2\.[1-4] \`${component}\`" "$GP"; then
      pass "gap-prioritization declares '${component}' component"
    else
      fail "gap-prioritization declares '${component}' component"
    fi
  done
  # w_p floor — priority must dominate gap ranking.
  if grep -q "w_p >= 0.3" "$GP"; then
    pass "gap-prioritization enforces w_p >= 0.3 floor"
  else
    fail "gap-prioritization enforces w_p >= 0.3 floor"
  fi
fi

# observability-analyzer (S3-13) sidecar + parsers + anomaly catalog.
OBA_SKILL="$SKILLS_DIR/observability-analyzer"
[[ -f "$OBA_SKILL/SKILL.md" ]] && pass "observability-analyzer SKILL.md present" \
  || fail "observability-analyzer SKILL.md present"
[[ -f "$OBA_SKILL/references/source-parsers.md" ]] \
  && pass "observability-analyzer source-parsers.md present" \
  || fail "observability-analyzer source-parsers.md present"
[[ -f "$OBA_SKILL/references/anomaly-rules.md" ]] \
  && pass "observability-analyzer anomaly-rules.md present" \
  || fail "observability-analyzer anomaly-rules.md present"

# Gate contract — zero critical anomalies in P0, console errors,
# web vitals within budget. Three-rule compose.
if grep -q "Zero critical anomalies in P0 scenarios" "$OBA_SKILL/SKILL.md" \
   && grep -q "console errors above the severity threshold" "$OBA_SKILL/SKILL.md" \
   && grep -q "web vitals meet the domain budget" "$OBA_SKILL/SKILL.md"; then
  pass "observability-analyzer gate: critical + console + web vitals"
else
  fail "observability-analyzer gate: critical + console + web vitals"
fi

# Source parsers — 4 formats form a closed set.
SP="$OBA_SKILL/references/source-parsers.md"
if [[ -f "$SP" ]]; then
  for format in "HAR 1.2" "Playwright trace" "Browser console" "Chrome DevTools Protocol"; do
    if grep -qE "^## [0-9]\. ${format}" "$SP"; then
      pass "source-parsers declares '${format}' format"
    else
      fail "source-parsers declares '${format}' format"
    fi
  done
  # Normalized TraceEvent shape — the cross-parser interface must be
  # declared so the parser layer stays stateless.
  if grep -q "Normalized \`TraceEvent\` shape" "$SP"; then
    pass "source-parsers declares normalized TraceEvent shape"
  else
    fail "source-parsers declares normalized TraceEvent shape"
  fi
fi

# Anomaly catalog — 5 categories form a closed set. Dropping one means
# a whole class of signals silently stops being measured.
AR="$OBA_SKILL/references/anomaly-rules.md"
if [[ -f "$AR" ]]; then
  for category in "Network anomalies" "Console anomalies" "Performance anomalies" "Security anomalies" "Third-party anomalies"; do
    if grep -qE "^## [0-9]\. ${category}" "$AR"; then
      pass "anomaly-rules has '${category}' category"
    else
      fail "anomaly-rules has '${category}' category"
    fi
  done
  # Rule count floor — below 10 means someone deleted a section.
  RULE_COUNT="$(grep -cE '^### [A-Z][A-Z0-9_-]+$' "$AR")"
  if (( RULE_COUNT >= 10 )); then
    pass "anomaly-rules has at least 10 rules (got $RULE_COUNT)"
  else
    fail "anomaly-rules has at least 10 rules (got $RULE_COUNT)"
  fi
  # Domain overrides table — promotes warnings to critical in specific
  # domains. Silent edit = wrong severity in production.
  if grep -q "Domain overrides" "$AR"; then
    pass "anomaly-rules declares domain overrides table"
  else
    fail "anomaly-rules declares domain overrides table"
  fi
  # Override-can-only-tighten rule — same discipline as every other
  # VibeFlow gate.
  if grep -q "rule MORE strict, never less" "$AR"; then
    pass "anomaly-rules: domain overrides can only tighten"
  else
    fail "anomaly-rules: domain overrides can only tighten"
  fi
fi

# visual-ai-analyzer (S3-14) sidecar + confidence/mode/catalog guards.
VAI_SKILL="$SKILLS_DIR/visual-ai-analyzer"
[[ -f "$VAI_SKILL/SKILL.md" ]] && pass "visual-ai-analyzer SKILL.md present" \
  || fail "visual-ai-analyzer SKILL.md present"
[[ -f "$VAI_SKILL/references/inspection-modes.md" ]] \
  && pass "visual-ai-analyzer inspection-modes.md present" \
  || fail "visual-ai-analyzer inspection-modes.md present"
[[ -f "$VAI_SKILL/references/finding-catalog.md" ]] \
  && pass "visual-ai-analyzer finding-catalog.md present" \
  || fail "visual-ai-analyzer finding-catalog.md present"

# Gate contract — zero critical P0 regressions + accessibility + design
# drift. Same three-rule compose shape as coverage/observability.
if grep -q "Zero critical visual regressions in P0 scenarios" "$VAI_SKILL/SKILL.md" \
   && grep -q "accessibility findings require remediation" "$VAI_SKILL/SKILL.md" \
   && grep -q "design-diff above tolerance needs human review" "$VAI_SKILL/SKILL.md"; then
  pass "visual-ai-analyzer gate: P0 critical + a11y + design drift"
else
  fail "visual-ai-analyzer gate: P0 critical + a11y + design drift"
fi

# Three inspection modes form a closed set. Dropping one silently
# removes a whole mode of vision analysis.
IM="$VAI_SKILL/references/inspection-modes.md"
if [[ -f "$IM" ]]; then
  for mode in "baseline-diff" "standalone" "design-comparison"; do
    if grep -qE "^## [0-9]\. \`${mode}\`" "$IM"; then
      pass "inspection-modes declares '${mode}' mode"
    else
      fail "inspection-modes declares '${mode}' mode"
    fi
  done
  # Modes are additive not exclusive — the key design decision that
  # lets a single run engage multiple modes.
  if grep -q "additive, not" "$IM" && grep -q "exclusive" "$IM"; then
    pass "inspection-modes are additive, not exclusive"
  else
    fail "inspection-modes are additive, not exclusive"
  fi
fi

# Finding catalog — 7 categories form a closed set.
FC="$VAI_SKILL/references/finding-catalog.md"
if [[ -f "$FC" ]]; then
  for category in "Layout findings" "Typography findings" "Color \+ contrast findings" "Alignment findings" "Overflow findings" "Broken-state findings"; do
    if grep -qE "^## [0-9]\. ${category}" "$FC"; then
      pass "finding-catalog has '${category}' category"
    else
      fail "finding-catalog has '${category}' category"
    fi
  done
  # Confidence-filter thresholds — structural rule that keeps the
  # vision model's hallucinations off the critical path.
  if grep -q "0.6 / 0.8" "$FC" || grep -q "confidence >= 0.8" "$FC"; then
    pass "finding-catalog declares confidence filter thresholds"
  else
    fail "finding-catalog declares confidence filter thresholds"
  fi
  # Finding count floor — below 12 means someone deleted entries.
  FIND_COUNT="$(grep -cE "^### [A-Z][A-Z0-9-]+$" "$FC")"
  if (( FIND_COUNT >= 12 )); then
    pass "finding-catalog has at least 12 finding entries (got $FIND_COUNT)"
  else
    fail "finding-catalog has at least 12 finding entries (got $FIND_COUNT)"
  fi
  # UNCLASSIFIED fallback must exist — same rule as every other
  # VibeFlow taxonomy.
  if grep -q "UNCLASSIFIED-VISUAL" "$FC"; then
    pass "finding-catalog declares UNCLASSIFIED-VISUAL fallback"
  else
    fail "finding-catalog declares UNCLASSIFIED-VISUAL fallback"
  fi
fi

# learning-loop-engine (S3-15) — first L3 skill. Sidecar + modes +
# pattern catalog + maturity stages guards.
LLE_SKILL="$SKILLS_DIR/learning-loop-engine"
[[ -f "$LLE_SKILL/SKILL.md" ]] && pass "learning-loop-engine SKILL.md present" \
  || fail "learning-loop-engine SKILL.md present"
[[ -f "$LLE_SKILL/references/pattern-detection.md" ]] \
  && pass "learning-loop-engine pattern-detection.md present" \
  || fail "learning-loop-engine pattern-detection.md present"
[[ -f "$LLE_SKILL/references/maturity-stages.md" ]] \
  && pass "learning-loop-engine maturity-stages.md present" \
  || fail "learning-loop-engine maturity-stages.md present"

# Gate contract — 3 invariants: every pattern ≥ 3 observations,
# every production bug traces, every recommendation actionable.
if grep -q "Every pattern must have ≥ 3 supporting observations" "$LLE_SKILL/SKILL.md" \
   && grep -q "Every production bug must trace to a specific test gap" "$LLE_SKILL/SKILL.md" \
   && grep -q "Every recommendation must be actionable" "$LLE_SKILL/SKILL.md"; then
  pass "learning-loop-engine gate: 3 observations + production trace + actionable"
else
  fail "learning-loop-engine gate: 3 observations + production trace + actionable"
fi

# 3 modes form a closed set — dropping one removes a whole analysis
# flow from the skill.
if grep -q "Mode 1: \`test-history\`" "$LLE_SKILL/SKILL.md" \
   && grep -q "Mode 2: \`production-feedback\`" "$LLE_SKILL/SKILL.md" \
   && grep -q "Mode 3: \`drift-analysis\`" "$LLE_SKILL/SKILL.md"; then
  pass "learning-loop-engine declares 3 modes (test-history/production-feedback/drift-analysis)"
else
  fail "learning-loop-engine declares 3 modes (test-history/production-feedback/drift-analysis)"
fi

# Pattern catalog — 3 mode-scoped sections. Dropping a section silently
# removes a mode's analysis capability.
PD="$LLE_SKILL/references/pattern-detection.md"
if [[ -f "$PD" ]]; then
  for section in "\`test-history\` mode patterns" "\`production-feedback\` mode patterns" "\`drift-analysis\` mode patterns"; do
    if grep -qE "^## [0-9]\. ${section}" "$PD"; then
      pass "pattern-detection has '${section}' section"
    else
      fail "pattern-detection has '${section}' section"
    fi
  done
  # Pattern count floor — below 10 means someone deleted entries.
  PATTERN_COUNT="$(grep -cE '^### LEARNING-' "$PD")"
  if (( PATTERN_COUNT >= 10 )); then
    pass "pattern-detection has at least 10 patterns (got $PATTERN_COUNT)"
  else
    fail "pattern-detection has at least 10 patterns (got $PATTERN_COUNT)"
  fi
  # Minimum-evidence non-negotiable rule — patterns need ≥ 3 observations.
  if grep -q "≥ 3, always" "$PD" || grep -q "at least.*3.*observations" "$PD"; then
    pass "pattern-detection enforces ≥ 3 observation floor"
  else
    fail "pattern-detection enforces ≥ 3 observation floor"
  fi
fi

# Maturity stages — 5 stages form a closed set.
MS="$LLE_SKILL/references/maturity-stages.md"
if [[ -f "$MS" ]]; then
  for stage in "Ad hoc" "Baseline" "Coverage" "Learning" "Self-improving"; do
    if grep -qE "^## Stage [1-5] — ${stage}" "$MS"; then
      pass "maturity-stages declares 'Stage ${stage}'"
    else
      fail "maturity-stages declares 'Stage ${stage}'"
    fi
  done
  # No Stage 6 — terminal stage rule. Silent addition of a Stage 6
  # would let teams chase gates indefinitely.
  if grep -q "There's no Stage 6" "$MS" || grep -q "terminal state by design" "$MS"; then
    pass "maturity-stages declares Stage 5 as terminal"
  else
    fail "maturity-stages declares Stage 5 as terminal"
  fi
  # Single-unmet-criterion blocks promotion — structural rule.
  if grep -q "single unmet criterion blocks promotion" "$MS" || grep -q "no partial credit" "$MS"; then
    pass "maturity-stages: single unmet criterion blocks promotion"
  else
    fail "maturity-stages: single unmet criterion blocks promotion"
  fi
fi

# decision-recommender (S3-16) — second L3 skill. Sidecar + gate
# + decision types + option generators + structural guards.
DR_SKILL="$SKILLS_DIR/decision-recommender"
[[ -f "$DR_SKILL/SKILL.md" ]] && pass "decision-recommender SKILL.md present" \
  || fail "decision-recommender SKILL.md present"
[[ -f "$DR_SKILL/references/decision-types.md" ]] \
  && pass "decision-recommender decision-types.md present" \
  || fail "decision-recommender decision-types.md present"
[[ -f "$DR_SKILL/references/option-generators.md" ]] \
  && pass "decision-recommender option-generators.md present" \
  || fail "decision-recommender option-generators.md present"

# Gate contract — 4 invariants. Every recommendation cites findings,
# every option has both-direction trade-offs, Option 0 always included,
# confidence < 0.7 escapes to human-judgment-needed.
if grep -q "Every option has at least one positive AND one" "$DR_SKILL/SKILL.md" \
   && grep -q "Option 0 is ALWAYS \"do nothing\"" "$DR_SKILL/SKILL.md" \
   && grep -q "Every recommendation cites at least one finding by" "$DR_SKILL/SKILL.md" \
   && grep -q "human-judgment-needed" "$DR_SKILL/SKILL.md"; then
  pass "decision-recommender gate: 4 invariants (tradeoffs + OPT-0 + cite + confidence)"
else
  fail "decision-recommender gate: 4 invariants (tradeoffs + OPT-0 + cite + confidence)"
fi

# Anti-AI-confidence rule — the skill explicitly refuses to ship a
# single weighted composite score.
if grep -q "NEVER computes a single weighted composite score" "$DR_SKILL/SKILL.md" \
   || grep -q "single-score framing" "$DR_SKILL/SKILL.md" \
   || grep -q "single weighted score that \"solves\"" "$DR_SKILL/SKILL.md"; then
  pass "decision-recommender rejects single-score framing"
else
  fail "decision-recommender rejects single-score framing"
fi

# Decision types — 5 canonical types + 1 UNCLASSIFIED fallback.
DT="$DR_SKILL/references/decision-types.md"
if [[ -f "$DT" ]]; then
  for dtype in "release-go-no-go" "gate-adjustment" "priority-change" "risk-acceptance" "scope-change"; do
    if grep -qE "^## [0-9]\. \`${dtype}\`" "$DT"; then
      pass "decision-types declares '${dtype}'"
    else
      fail "decision-types declares '${dtype}'"
    fi
  done
  # UNCLASSIFIED-DECISION fallback
  if grep -q "UNCLASSIFIED-DECISION" "$DT"; then
    pass "decision-types declares UNCLASSIFIED-DECISION fallback"
  else
    fail "decision-types declares UNCLASSIFIED-DECISION fallback"
  fi
  # Walk order declared (specific to general)
  if grep -q "Walk order" "$DT" || grep -q "walk order" "$DT"; then
    pass "decision-types declares walk order"
  else
    fail "decision-types declares walk order"
  fi
fi

# Option generators — 5 generators (one per type) + shared validation.
OG="$DR_SKILL/references/option-generators.md"
if [[ -f "$OG" ]]; then
  for gen in "release-options" "gate-options" "priority-options" "risk-options" "scope-options"; do
    if grep -qE "^## [0-9]\. \`${gen}\`" "$OG"; then
      pass "option-generators declares '${gen}' generator"
    else
      fail "option-generators declares '${gen}' generator"
    fi
  done
  # Structural rule: OPT-0 always Do Nothing — the load-bearing rule.
  if grep -q "OPT-0 — Do nothing" "$OG" || grep -q "OPT-0 is ALWAYS" "$OG"; then
    pass "option-generators enforces 'OPT-0 always Do Nothing'"
  else
    fail "option-generators enforces 'OPT-0 always Do Nothing'"
  fi
  # Validation rules for positive/negative/unknown trade-offs
  if grep -q "positive.length >= 1" "$OG" && grep -q "negative.length >= 1" "$OG"; then
    pass "option-generators enforces positive + negative tradeoff validation"
  else
    fail "option-generators enforces positive + negative tradeoff validation"
  fi
fi

# reconciliation-simulator (S3-17) — L1 financial-domain-only simulator.
# Sidecars + gate contract + canonical invariants + concurrency patterns
# + structural guards (financial-only, deterministic, severity critical).
RS_SKILL="$SKILLS_DIR/reconciliation-simulator"
[[ -f "$RS_SKILL/SKILL.md" ]] && pass "reconciliation-simulator SKILL.md present" \
  || fail "reconciliation-simulator SKILL.md present"
[[ -f "$RS_SKILL/references/ledger-invariants.md" ]] \
  && pass "reconciliation-simulator ledger-invariants.md present" \
  || fail "reconciliation-simulator ledger-invariants.md present"
[[ -f "$RS_SKILL/references/concurrency-scenarios.md" ]] \
  && pass "reconciliation-simulator concurrency-scenarios.md present" \
  || fail "reconciliation-simulator concurrency-scenarios.md present"

# Gate contract — zero invariant violations, deterministic simulation,
# every violation traces to a specific operation sequence.
if grep -q "zero invariant violations across every" "$RS_SKILL/SKILL.md" \
   && grep -q "deterministic simulation" "$RS_SKILL/SKILL.md" \
   && grep -q "every violation traces to a specific" "$RS_SKILL/SKILL.md"; then
  pass "reconciliation-simulator gate contract (zero violations + deterministic + traces)"
else
  fail "reconciliation-simulator gate contract (zero violations + deterministic + traces)"
fi

# Financial-domain-only rule — no override flag, block on any other domain.
if grep -q "financial-only" "$RS_SKILL/SKILL.md" \
   && grep -q "No .*override" "$RS_SKILL/SKILL.md"; then
  pass "reconciliation-simulator: financial-only + no override"
else
  fail "reconciliation-simulator: financial-only + no override"
fi

# Every-step invariant check rule — the torn-state detection.
if grep -q "Every step is checked, not just the endpoints" "$RS_SKILL/SKILL.md"; then
  pass "reconciliation-simulator: every step checked, not just endpoints"
else
  fail "reconciliation-simulator: every step checked, not just endpoints"
fi

# All violations are severity: critical (no warning band).
if grep -q "Every violation is .severity: critical" "$RS_SKILL/SKILL.md"; then
  pass "reconciliation-simulator: every violation severity critical"
else
  fail "reconciliation-simulator: every violation severity critical"
fi

# Determinism is a structural contract, not best-effort.
if grep -q "structural contract" "$RS_SKILL/SKILL.md" \
   && grep -q "best-effort property" "$RS_SKILL/SKILL.md"; then
  pass "reconciliation-simulator: determinism is a structural contract"
else
  fail "reconciliation-simulator: determinism is a structural contract"
fi

# Canonical ledger invariants — all 6 present in the sidecar.
LI="$RS_SKILL/references/ledger-invariants.md"
if [[ -f "$LI" ]]; then
  for inv in "LEDGER-DOUBLE-ENTRY" "LEDGER-CONSERVATION" "LEDGER-SIGN-CONVENTION" \
             "LEDGER-MONETARY-PRECISION" "LEDGER-NON-NEGATIVE-BALANCE" \
             "LEDGER-AUTHORITATIVE-TIME"; do
    if grep -qE "^## [0-9]\. ${inv}" "$LI"; then
      pass "ledger-invariants declares '${inv}'"
    else
      fail "ledger-invariants declares '${inv}'"
    fi
  done
  # No-contradiction composition rule for per-project invariants.
  if grep -q "No contradiction" "$LI" && grep -q "Strengthening is allowed" "$LI"; then
    pass "ledger-invariants: composition (no-contradiction + strengthening-allowed)"
  else
    fail "ledger-invariants: composition (no-contradiction + strengthening-allowed)"
  fi
  # Frozen set — additions require retrospective + version bump.
  if grep -q "ledgerInvariantsVersion" "$LI"; then
    pass "ledger-invariants declares ledgerInvariantsVersion"
  else
    fail "ledger-invariants declares ledgerInvariantsVersion"
  fi
fi

# Canonical concurrency patterns — all 6 present in the sidecar.
CS="$RS_SKILL/references/concurrency-scenarios.md"
if [[ -f "$CS" ]]; then
  for pat in "CONCURRENT-DEBITS-SAME-ACCOUNT" "CONCURRENT-TRANSFERS-RING" \
             "RETRY-ON-FAILURE" "PARTIAL-REVERSAL" "TIMEOUT-DURING-COMMIT" \
             "DEAD-LEG"; do
    if grep -qE "^## [0-9]\. ${pat}" "$CS"; then
      pass "concurrency-scenarios declares '${pat}'"
    else
      fail "concurrency-scenarios declares '${pat}'"
    fi
  done
  # Cooperative scheduler + seed-deterministic rule.
  if grep -q "cooperative scheduler" "$CS" && grep -q "seed-deterministic" "$CS"; then
    pass "concurrency-scenarios: cooperative scheduler + seed-deterministic"
  else
    fail "concurrency-scenarios: cooperative scheduler + seed-deterministic"
  fi
  # Pattern removal explicitly forbidden — anti-drift guard.
  if grep -q "Removing a canonical pattern is not allowed" "$CS"; then
    pass "concurrency-scenarios: removing patterns forbidden"
  else
    fail "concurrency-scenarios: removing patterns forbidden"
  fi
  if grep -q "concurrencyScenariosVersion" "$CS"; then
    pass "concurrency-scenarios declares concurrencyScenariosVersion"
  else
    fail "concurrency-scenarios declares concurrencyScenariosVersion"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [2] hooks.json references =="

if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json is valid JSON"
else
  fail "hooks.json is valid JSON"
fi

# Collect every command from hooks.json and check the resolved script exists.
# We never split on spaces — hook commands are always a single script path,
# and REPO_ROOT may legitimately contain spaces.
MISSING_HOOKS=0
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  script="${cmd/\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT}"
  if [[ ! -f "$script" ]]; then
    MISSING_HOOKS=$((MISSING_HOOKS + 1))
    echo "    missing hook script: $script"
  elif [[ ! -x "$script" ]]; then
    MISSING_HOOKS=$((MISSING_HOOKS + 1))
    echo "    hook not executable: $script"
  fi
done < <(jq -r '.. | objects | .command // empty' "$HOOKS_JSON")
assert_eq "every hook script exists and is executable" "0" "$MISSING_HOOKS"

# ---------------------------------------------------------------------------
echo "== [3] .mcp.json + MCP server builds =="

if jq -e . "$MCP_JSON" >/dev/null 2>&1; then
  pass ".mcp.json is valid JSON"
else
  fail ".mcp.json is valid JSON"
fi

ENGINE_REL_ARG="$(jq -r '.mcpServers."sdlc-engine".args[0]' "$MCP_JSON")"
ENGINE_RESOLVED="$REPO_ROOT/${ENGINE_REL_ARG#./}"
[[ -f "$ENGINE_RESOLVED" ]] && pass ".mcp.json sdlc-engine points to a real dist file" \
  || fail ".mcp.json sdlc-engine points to a real dist file ($ENGINE_RESOLVED)"

CI_REL_ARG="$(jq -r '.mcpServers."codebase-intel".args[0]' "$MCP_JSON")"
CI_RESOLVED="$REPO_ROOT/${CI_REL_ARG#./}"
[[ -f "$CI_RESOLVED" ]] && pass ".mcp.json codebase-intel points to a real dist file" \
  || fail ".mcp.json codebase-intel points to a real dist file ($CI_RESOLVED)"

DB_REL_ARG="$(jq -r '.mcpServers."design-bridge".args[0]' "$MCP_JSON")"
DB_RESOLVED="$REPO_ROOT/${DB_REL_ARG#./}"
[[ -f "$DB_RESOLVED" ]] && pass ".mcp.json design-bridge points to a real dist file" \
  || fail ".mcp.json design-bridge points to a real dist file ($DB_RESOLVED)"

DO_REL_ARG="$(jq -r '.mcpServers."dev-ops".args[0]' "$MCP_JSON")"
DO_RESOLVED="$REPO_ROOT/${DO_REL_ARG#./}"
[[ -f "$DO_RESOLVED" ]] && pass ".mcp.json dev-ops points to a real dist file" \
  || fail ".mcp.json dev-ops points to a real dist file ($DO_RESOLVED)"

OB_REL_ARG="$(jq -r '.mcpServers."observability".args[0]' "$MCP_JSON")"
OB_RESOLVED="$REPO_ROOT/${OB_REL_ARG#./}"
[[ -f "$OB_RESOLVED" ]] && pass ".mcp.json observability points to a real dist file" \
  || fail ".mcp.json observability points to a real dist file ($OB_RESOLVED)"

# design-bridge must flow the Figma token from userConfig, never hardcoded
# (Bug #7 regression guard).
DB_TOKEN_SRC="$(jq -r '.mcpServers."design-bridge".env.FIGMA_TOKEN' "$MCP_JSON")"
if [[ "$DB_TOKEN_SRC" == "\${userConfig.figma_token}" ]]; then
  pass "design-bridge FIGMA_TOKEN flows from userConfig (Bug #7 guard)"
else
  fail "design-bridge FIGMA_TOKEN flows from userConfig (got: $DB_TOKEN_SRC)"
fi
if jq -e '.userConfig.figma_token.sensitive == true' "$PLUGIN_JSON" >/dev/null; then
  pass "plugin.json figma_token declared sensitive"
else
  fail "plugin.json figma_token declared sensitive"
fi

# dev-ops must flow the GitHub token the same way. Same regression shape:
# if somebody ever inlines a token here, CI fails fast.
DO_TOKEN_SRC="$(jq -r '.mcpServers."dev-ops".env.GITHUB_TOKEN' "$MCP_JSON")"
if [[ "$DO_TOKEN_SRC" == "\${userConfig.github_token}" ]]; then
  pass "dev-ops GITHUB_TOKEN flows from userConfig"
else
  fail "dev-ops GITHUB_TOKEN flows from userConfig (got: $DO_TOKEN_SRC)"
fi
if jq -e '.userConfig.github_token.sensitive == true' "$PLUGIN_JSON" >/dev/null; then
  pass "plugin.json github_token declared sensitive"
else
  fail "plugin.json github_token declared sensitive"
fi

# Sanity: every MCP server dist is a valid node module.
if node --check "$ENGINE_DIST" 2>/dev/null; then
  pass "sdlc-engine dist parses as valid JS"
else
  fail "sdlc-engine dist parses as valid JS"
fi
if node --check "$CI_DIST" 2>/dev/null; then
  pass "codebase-intel dist parses as valid JS"
else
  fail "codebase-intel dist parses as valid JS"
fi
if node --check "$DB_DIST" 2>/dev/null; then
  pass "design-bridge dist parses as valid JS"
else
  fail "design-bridge dist parses as valid JS"
fi
if node --check "$DO_DIST" 2>/dev/null; then
  pass "dev-ops dist parses as valid JS"
else
  fail "dev-ops dist parses as valid JS"
fi
if node --check "$OB_DIST" 2>/dev/null; then
  pass "observability dist parses as valid JS"
else
  fail "observability dist parses as valid JS"
fi

# ---------------------------------------------------------------------------
echo "== [4] sdlc-engine stdio smoke test =="

# Spawn the engine on a temp state.db, exchange JSON-RPC messages.
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-int-smoke-XXXXXX")"
export VIBEFLOW_SQLITE_PATH="$SMOKE_DIR/state.db"
export VIBEFLOW_PROJECT="smoke"
export VIBEFLOW_MODE="solo"

SMOKE_OUT="$(node "$ENGINE_DIST" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_list_phases","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"smoke"}}}
EOF
)"

# The MCP SDK writes one JSON-RPC response per line. Check the three we care
# about showed up correctly.
TOOL_LIST_LINE="$(echo "$SMOKE_OUT" | grep '"id":2')"
LIST_PHASES_LINE="$(echo "$SMOKE_OUT" | grep '"id":3')"
GET_STATE_LINE="$(echo "$SMOKE_OUT" | grep '"id":4')"

assert_contains "tools/list returns sdlc_list_phases" "sdlc_list_phases" "$TOOL_LIST_LINE"
assert_contains "tools/list returns sdlc_advance_phase" "sdlc_advance_phase" "$TOOL_LIST_LINE"
assert_contains "list_phases returns REQUIREMENTS" "REQUIREMENTS" "$LIST_PHASES_LINE"
assert_contains "list_phases returns DEPLOYMENT" "DEPLOYMENT" "$LIST_PHASES_LINE"
# Content is a pretty-printed JSON string wrapped inside the MCP envelope;
# simple substring checks on the escaped content are sufficient.
assert_contains "get_state returns projectId smoke" 'projectId' "$GET_STATE_LINE"
assert_contains "get_state body names the smoke project" 'smoke' "$GET_STATE_LINE"
assert_contains "get_state starts at REQUIREMENTS" 'REQUIREMENTS' "$GET_STATE_LINE"

rm -rf "$SMOKE_DIR"
unset VIBEFLOW_SQLITE_PATH VIBEFLOW_PROJECT VIBEFLOW_MODE

# ---------------------------------------------------------------------------
echo "== [4b] codebase-intel stdio smoke test =="

# Build a tiny TS fixture the server can analyze, then drive it via JSON-RPC.
CI_SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-int-ci-XXXXXX")"
cat > "$CI_SMOKE_DIR/package.json" <<'PKG'
{"name":"ci-smoke","version":"1.0.0","dependencies":{"fastify":"^4.0.0"}}
PKG
cat > "$CI_SMOKE_DIR/tsconfig.json" <<'TS'
{"compilerOptions":{"target":"ES2022"}}
TS
mkdir -p "$CI_SMOKE_DIR/src"
printf 'import { b } from "./b";\nexport const a = b;\n' > "$CI_SMOKE_DIR/src/a.ts"
printf 'export const b = 1;\n// TODO: replace placeholder\n' > "$CI_SMOKE_DIR/src/b.ts"

CI_SMOKE_OUT="$(node "$CI_DIST" <<EOF 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ci_analyze_structure","arguments":{"root":"$CI_SMOKE_DIR"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"ci_dependency_graph","arguments":{"root":"$CI_SMOKE_DIR"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ci_tech_debt_scan","arguments":{"root":"$CI_SMOKE_DIR"}}}
EOF
)"

CI_LIST_LINE="$(echo "$CI_SMOKE_OUT" | grep '"id":2')"
CI_ANALYZE_LINE="$(echo "$CI_SMOKE_OUT" | grep '"id":3')"
CI_GRAPH_LINE="$(echo "$CI_SMOKE_OUT" | grep '"id":4')"
CI_DEBT_LINE="$(echo "$CI_SMOKE_OUT" | grep '"id":5')"

assert_contains "tools/list returns ci_analyze_structure" "ci_analyze_structure" "$CI_LIST_LINE"
assert_contains "tools/list returns ci_dependency_graph" "ci_dependency_graph" "$CI_LIST_LINE"
assert_contains "tools/list returns ci_find_hotspots" "ci_find_hotspots" "$CI_LIST_LINE"
assert_contains "tools/list returns ci_tech_debt_scan" "ci_tech_debt_scan" "$CI_LIST_LINE"
assert_contains "analyze_structure detects typescript" "typescript" "$CI_ANALYZE_LINE"
assert_contains "analyze_structure detects fastify" "fastify" "$CI_ANALYZE_LINE"
assert_contains "dependency_graph returns an edge" "src/a.ts" "$CI_GRAPH_LINE"
assert_contains "tech_debt_scan surfaces TODO marker" "TODO" "$CI_DEBT_LINE"

rm -rf "$CI_SMOKE_DIR"

# ---------------------------------------------------------------------------
echo "== [4c] design-bridge stdio smoke test =="

# The server lazily constructs its Figma client, so list_tools and
# db_compare_impl (filesystem-only) work without a real token. We still set
# a throwaway FIGMA_TOKEN so the client can build when the token-dependent
# path is exercised from unit tests.
DB_SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-int-db-XXXXXX")"
LEFT_PNG="$DB_SMOKE_DIR/left.png"
RIGHT_PNG="$DB_SMOKE_DIR/right.png"
# Minimal valid PNG (signature + IHDR chunk, 100×50). Matches the pngStub()
# helper in tests/compare.test.ts — kept in sync by hand.
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x64\x00\x00\x00\x32\x08\x02\x00\x00\x00' > "$LEFT_PNG"
cp "$LEFT_PNG" "$RIGHT_PNG"
DIFF_PNG="$DB_SMOKE_DIR/diff.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\xc8\x00\x00\x00\x64\x08\x02\x00\x00\x00' > "$DIFF_PNG"

DB_SMOKE_OUT="$(FIGMA_TOKEN=test-token node "$DB_DIST" <<EOF 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"db_compare_impl","arguments":{"leftPath":"$LEFT_PNG","rightPath":"$RIGHT_PNG"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"db_compare_impl","arguments":{"leftPath":"$LEFT_PNG","rightPath":"$DIFF_PNG"}}}
EOF
)"

DB_LIST_LINE="$(echo "$DB_SMOKE_OUT" | grep '"id":2')"
DB_IDENT_LINE="$(echo "$DB_SMOKE_OUT" | grep '"id":3')"
DB_DIFF_LINE="$(echo "$DB_SMOKE_OUT" | grep '"id":4')"

assert_contains "tools/list returns db_fetch_design" "db_fetch_design" "$DB_LIST_LINE"
assert_contains "tools/list returns db_extract_tokens" "db_extract_tokens" "$DB_LIST_LINE"
assert_contains "tools/list returns db_generate_styles" "db_generate_styles" "$DB_LIST_LINE"
assert_contains "tools/list returns db_compare_impl" "db_compare_impl" "$DB_LIST_LINE"
assert_contains "compare_impl identical verdict on matching PNGs" "identical" "$DB_IDENT_LINE"
assert_contains "compare_impl size-mismatch verdict on differing dims" "size-mismatch" "$DB_DIFF_LINE"

rm -rf "$DB_SMOKE_DIR"

# ---------------------------------------------------------------------------
echo "== [4d] dev-ops stdio smoke test =="

# dev-ops lazy-constructs the GitHub client at first call. list_tools is
# safe without a real token; we set a placeholder so the client builds
# when a tool call that needs it fires. The smoke does not actually
# dispatch a workflow — that would require a real repo/token pair.
DO_SMOKE_OUT="$(GITHUB_TOKEN=test-token node "$DO_DIST" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF
)"

DO_LIST_LINE="$(echo "$DO_SMOKE_OUT" | grep '"id":2')"

assert_contains "tools/list returns do_trigger_pipeline" "do_trigger_pipeline" "$DO_LIST_LINE"
assert_contains "tools/list returns do_pipeline_status" "do_pipeline_status" "$DO_LIST_LINE"
assert_contains "tools/list returns do_fetch_artifacts" "do_fetch_artifacts" "$DO_LIST_LINE"
assert_contains "tools/list returns do_deploy_staging" "do_deploy_staging" "$DO_LIST_LINE"
assert_contains "tools/list returns do_rollback" "do_rollback" "$DO_LIST_LINE"

# ---------------------------------------------------------------------------
echo "== [4e] observability stdio smoke test =="

# observability is a local/offline MCP — no env vars, no network. Feed it a
# tiny vitest-shaped inline payload and verify the metrics come back.
OB_SMOKE_OUT="$(node "$OB_DIST" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ob_collect_metrics","arguments":{"payload":{"numTotalTests":2,"startTime":0,"endTime":1000,"testResults":[{"testFilePath":"/app/src/a.ts","assertionResults":[{"title":"happy","fullName":"happy","status":"passed","duration":10,"failureMessages":[],"location":{"line":1,"column":1}},{"title":"sad","fullName":"sad","status":"failed","duration":20,"failureMessages":["boom"],"location":{"line":2,"column":1}}]}]}}}}
EOF
)"

OB_LIST_LINE="$(echo "$OB_SMOKE_OUT" | grep '"id":2')"
OB_METRICS_LINE="$(echo "$OB_SMOKE_OUT" | grep '"id":3')"

assert_contains "tools/list returns ob_collect_metrics" "ob_collect_metrics" "$OB_LIST_LINE"
assert_contains "tools/list returns ob_track_flaky" "ob_track_flaky" "$OB_LIST_LINE"
assert_contains "tools/list returns ob_perf_trend" "ob_perf_trend" "$OB_LIST_LINE"
assert_contains "tools/list returns ob_health_dashboard" "ob_health_dashboard" "$OB_LIST_LINE"
# The result travels back as a pretty-printed JSON string inside the MCP
# text envelope, so fields appear as escaped `\"passed\": 1`. Match the
# escaped form literally via a single-quoted needle.
assert_contains "collect_metrics parses an inline vitest payload" 'passed\": 1' "$OB_METRICS_LINE"
assert_contains "collect_metrics counts failures" 'failed\": 1' "$OB_METRICS_LINE"
assert_contains "collect_metrics auto-detects vitest" "vitest" "$OB_METRICS_LINE"

# ---------------------------------------------------------------------------
echo "== [5] engine + hooks e2e flow =="

E2E_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vf-int-e2e-XXXXXX")"
cleanup_e2e() { rm -rf "$E2E_DIR"; }
trap cleanup_e2e EXIT

cat > "$E2E_DIR/vibeflow.config.json" <<'JSON'
{"project":"e2e","mode":"solo","domain":"general","currentPhase":"REQUIREMENTS"}
JSON
mkdir -p "$E2E_DIR/.vibeflow"

# Drive the engine through one full advance via a tiny node script that uses
# the same modules the MCP server wires up. Tests the engine from the same
# entry point the tool handlers use.
node - <<NODE >/dev/null 2>&1
import { SqliteStateStore } from "$REPO_ROOT/mcp-servers/sdlc-engine/dist/state/sqlite.js";
import { SdlcEngine } from "$REPO_ROOT/mcp-servers/sdlc-engine/dist/engine.js";
import { PhaseRegistry } from "$REPO_ROOT/mcp-servers/sdlc-engine/dist/phases.js";

const store = new SqliteStateStore("$E2E_DIR/.vibeflow/state.db");
await store.init();
const engine = new SdlcEngine(store, new PhaseRegistry());
await engine.getOrInit("e2e");
await engine.satisfyCriterion({ projectId: "e2e", criterion: "prd.approved" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "testability.score>=60" });
await engine.recordConsensus({ projectId: "e2e", phase: "REQUIREMENTS", agreement: 0.95, criticalIssues: 0 });
await engine.advancePhase({ projectId: "e2e", to: "DESIGN" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "design.approved" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "accessibility.verified" });
await engine.recordConsensus({ projectId: "e2e", phase: "DESIGN", agreement: 0.95, criticalIssues: 0 });
await engine.advancePhase({ projectId: "e2e", to: "ARCHITECTURE" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "adr.recorded" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "consensus.approved" });
await engine.recordConsensus({ projectId: "e2e", phase: "ARCHITECTURE", agreement: 0.95, criticalIssues: 0 });
await engine.advancePhase({ projectId: "e2e", to: "PLANNING" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "test-strategy.approved" });
await engine.satisfyCriterion({ projectId: "e2e", criterion: "sprint.planned" });
await engine.recordConsensus({ projectId: "e2e", phase: "PLANNING", agreement: 0.95, criticalIssues: 0 });
await engine.advancePhase({ projectId: "e2e", to: "DEVELOPMENT" });
await store.close();
NODE
E2E_RC=$?
assert_eq "engine walked REQUIREMENTS → DEVELOPMENT" "0" "$E2E_RC"

# load-sdlc-context.sh must reflect the new phase.
export VIBEFLOW_CWD="$E2E_DIR"
CTX="$(bash "$REPO_ROOT/hooks/scripts/load-sdlc-context.sh")"
assert_contains "context reports DEVELOPMENT phase" "phase=DEVELOPMENT" "$CTX"

# commit-guard must NOW allow conformant commits (phase gate cleared).
INPUT='{"tool_input":{"command":"git commit -m \"feat: hello\""}}'
echo "$INPUT" | bash "$REPO_ROOT/hooks/scripts/commit-guard.sh" >/dev/null 2>/dev/null
assert_eq "commit-guard allows conformant commit in DEVELOPMENT" "0" "$?"

# ...but still reject malformed messages.
INPUT='{"tool_input":{"command":"git commit -m \"nope\""}}'
echo "$INPUT" | bash "$REPO_ROOT/hooks/scripts/commit-guard.sh" >/dev/null 2>/dev/null
assert_eq "commit-guard still rejects malformed message in DEVELOPMENT" "2" "$?"

unset VIBEFLOW_CWD

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
