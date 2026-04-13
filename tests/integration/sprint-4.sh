#!/bin/bash
# VibeFlow Sprint 4 integration harness.
#
# Complements run.sh + sprint-2.sh + sprint-3.sh. This harness proves
# the Sprint 4 polish/packaging invariants hold:
#
#   - every MCP server has a vitest.config.ts declaring 80/80/80/80
#     coverage thresholds and excluding the stdio bootstrap
#   - every MCP server passes its own coverage threshold today
#   - every MCP server has at least its current baseline test count
#     (regression guard)
#   - every io-standard output name is cited by its owning SKILL.md
#     (skill-output schema consistency)
#
# sprint-4.sh is heavier than the others because it actually runs
# coverage on every MCP. That's deliberate: "all MCPs >80% coverage"
# is a load-bearing Sprint-4 goal, and the cheapest way to keep it
# load-bearing is to re-measure it every time this harness runs.
#
# Exit 0 on full pass, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
IO_STANDARD="$SKILLS_DIR/_standards/io-standard.md"

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$1"); echo "  FAIL $1"; }

MCPS=(sdlc-engine codebase-intel design-bridge dev-ops observability)

# ---------------------------------------------------------------------------
echo "== [S4-A] MCP coverage configuration =="

for mcp in "${MCPS[@]}"; do
  cfg="$REPO_ROOT/mcp-servers/$mcp/vitest.config.ts"
  if [[ ! -f "$cfg" ]]; then
    fail "$mcp: vitest.config.ts present"
    continue
  fi
  pass "$mcp: vitest.config.ts present"

  # Coverage block present with v8 provider.
  if grep -q 'provider: "v8"' "$cfg"; then
    pass "$mcp: coverage provider is v8"
  else
    fail "$mcp: coverage provider is v8"
  fi

  # src/index.ts excluded — the stdio bootstrap is not testable from
  # vitest; the integration harness exercises it end-to-end instead.
  if grep -q '"src/index.ts"' "$cfg"; then
    pass "$mcp: src/index.ts excluded from coverage"
  else
    fail "$mcp: src/index.ts excluded from coverage"
  fi

  # Thresholds must be >= 80 on all 4 axes. We match the canonical
  # literal "80" — if a future PR tightens to 85, this sentinel must
  # be updated at the same time. (Tighten-only discipline, same shape
  # as every other VibeFlow threshold.)
  for axis in statements lines functions branches; do
    if grep -qE "${axis}:\s*80" "$cfg"; then
      pass "$mcp: coverage threshold $axis >= 80"
    else
      fail "$mcp: coverage threshold $axis >= 80"
    fi
  done
done

# ---------------------------------------------------------------------------
echo "== [S4-B] MCP coverage actually meets threshold =="

for mcp in "${MCPS[@]}"; do
  dir="$REPO_ROOT/mcp-servers/$mcp"
  pushd "$dir" >/dev/null
  if npx --no-install vitest run --coverage >/dev/null 2>&1; then
    pass "$mcp: vitest coverage threshold satisfied"
  else
    fail "$mcp: vitest coverage threshold satisfied"
  fi
  popd >/dev/null
done

# ---------------------------------------------------------------------------
echo "== [S4-C] MCP test count regression guard =="

# Baseline test counts — if a regression drops any of these, the
# harness fails loudly. Update these numbers ONLY when the real
# counts go up. Same discipline as hooks/tests/run.sh's count floors.
declare -a TEST_FLOORS=(
  "sdlc-engine:104"
  "codebase-intel:46"
  "design-bridge:54"
  "dev-ops:37"
  "observability:76"
)

for pair in "${TEST_FLOORS[@]}"; do
  mcp="${pair%%:*}"
  floor="${pair#*:}"
  dir="$REPO_ROOT/mcp-servers/$mcp"
  pushd "$dir" >/dev/null
  # Count `Tests  N passed` line from vitest's summary output.
  OUT="$(npx --no-install vitest run 2>&1)"
  popd >/dev/null
  count="$(echo "$OUT" | grep -oE 'Tests  [0-9]+ passed' | grep -oE '[0-9]+' | head -1)"
  if [[ -z "$count" ]]; then
    fail "$mcp: could not parse test count"
    continue
  fi
  if (( count >= floor )); then
    pass "$mcp: test count $count >= floor $floor"
  else
    fail "$mcp: test count $count dropped below floor $floor"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S4-D] io-standard output consistency =="

# For every skill named in io-standard.md's output table, the
# corresponding SKILL.md must cite the output. Drift here produces
# skills that "declare" outputs their SKILL.md doesn't actually
# discuss — which is how downstream consumers wire up to phantom
# outputs.
if [[ ! -f "$IO_STANDARD" ]]; then
  fail "io-standard.md exists"
else
  pass "io-standard.md exists"
fi

# Map of (skill → primary output) from io-standard.md. Hand-maintained
# to keep the sentinel specific — a broader auto-extraction would drown
# in false positives on section headers and link text.
declare -a SKILL_OUTPUTS=(
  "prd-quality-analyzer:prd-quality-report.md"
  "traceability-engine:rtm"
  "test-strategy-planner:test-strategy.md"
  "architecture-validator:architecture-report.md"
  "component-test-writer:test"
  "contract-test-writer:contract-report.md"
  "business-rule-validator:business-rules.md"
  "test-data-manager:factory"
  "invariant-formalizer:invariant-matrix.md"
  "checklist-generator:checklist-"
  "e2e-test-writer:spec.ts"
  "uat-executor:uat-raw-report.md"
  "test-result-analyzer:test-results.md"
  "regression-test-runner:regression-report.md"
  "test-priority-engine:priority-plan.md"
  "mutation-test-runner:mutation-report.md"
  "environment-orchestrator:env-setup.md"
  "chaos-injector:chaos-report.md"
  "cross-run-consistency:consistency-report.md"
  "coverage-analyzer:coverage-report.md"
  "visual-ai-analyzer:visual-report.md"
  "observability-analyzer:observability-report.md"
  "reconciliation-simulator:reconciliation-report.md"
  "decision-recommender:decision-package.md"
  "learning-loop-engine:learning-report.md"
)

for pair in "${SKILL_OUTPUTS[@]}"; do
  skill="${pair%%:*}"
  output="${pair#*:}"
  f="$SKILLS_DIR/$skill/SKILL.md"
  if [[ ! -f "$f" ]]; then
    fail "$skill SKILL.md exists"
    continue
  fi
  # io-standard.md must also declare the skill (sanity).
  if grep -q "^#### $skill" "$IO_STANDARD"; then
    pass "io-standard.md declares $skill"
  else
    fail "io-standard.md declares $skill"
  fi
  if grep -qF "$output" "$f"; then
    pass "$skill SKILL.md names output $output"
  else
    fail "$skill SKILL.md names output $output"
  fi
done

# ---------------------------------------------------------------------------
echo "== [S4-E] demo-app layout =="

# The S4-03 deliverable: examples/demo-app/ must exist with a full
# walkthrough layout. We check file presence and key contents so a
# future refactor can't silently delete half the demo and still pass CI.
DEMO="$REPO_ROOT/examples/demo-app"
DEMO_REQUIRED=(
  "README.md"
  "vibeflow.config.json"
  "package.json"
  "tsconfig.json"
  "vitest.config.ts"
  "docs/PRD.md"
  "docs/DEMO-WALKTHROUGH.md"
  "src/catalog.ts"
  "src/pricing.ts"
  "src/inventory.ts"
  "tests/catalog.test.ts"
  "tests/pricing.test.ts"
  "tests/inventory.test.ts"
  ".vibeflow/reports/prd-quality-report.md"
  ".vibeflow/reports/scenario-set.md"
  ".vibeflow/reports/test-strategy.md"
  ".vibeflow/reports/release-decision.md"
)
for rel in "${DEMO_REQUIRED[@]}"; do
  if [[ -f "$DEMO/$rel" ]]; then
    pass "demo-app: $rel present"
  else
    fail "demo-app: $rel present"
  fi
done

# vibeflow.config.json must declare the e-commerce domain — the demo's
# PRD and release-decision weights depend on it.
if [[ -f "$DEMO/vibeflow.config.json" ]]; then
  if jq -e '.domain == "e-commerce"' "$DEMO/vibeflow.config.json" >/dev/null 2>&1; then
    pass "demo-app: config domain is e-commerce"
  else
    fail "demo-app: config domain is e-commerce"
  fi
  if jq -e '.criticalPaths | index("src/pricing.ts") != null' "$DEMO/vibeflow.config.json" >/dev/null 2>&1; then
    pass "demo-app: pricing.ts declared as a critical path"
  else
    fail "demo-app: pricing.ts declared as a critical path"
  fi
fi

# PRD must name every requirement family (CAT/PRC/INV) so the rest of
# the pipeline has something to map onto.
if [[ -f "$DEMO/docs/PRD.md" ]]; then
  for fam in CAT-001 CAT-005 PRC-001 PRC-005 INV-001 INV-005; do
    if grep -q "$fam" "$DEMO/docs/PRD.md"; then
      pass "demo PRD declares $fam"
    else
      fail "demo PRD declares $fam"
    fi
  done
fi

# Pre-baked release decision must name a GO verdict with a composite score.
if [[ -f "$DEMO/.vibeflow/reports/release-decision.md" ]]; then
  if grep -q "GO — 92 / 100" "$DEMO/.vibeflow/reports/release-decision.md"; then
    pass "demo release-decision shows GO 92/100"
  else
    fail "demo release-decision shows GO 92/100"
  fi
fi

# Walkthrough must point at every skill in the happy path order so
# readers get the complete story.
if [[ -f "$DEMO/docs/DEMO-WALKTHROUGH.md" ]]; then
  for step in "prd-quality-analyzer" "test-strategy-planner" "scenario-generator" "advance" "release-decision-engine"; do
    if grep -q "vibeflow:$step" "$DEMO/docs/DEMO-WALKTHROUGH.md"; then
      pass "walkthrough mentions /vibeflow:$step"
    else
      fail "walkthrough mentions /vibeflow:$step"
    fi
  done
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
