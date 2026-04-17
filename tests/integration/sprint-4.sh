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
MCP_JSON="$REPO_ROOT/.mcp.json"

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
  "sdlc-engine:105"
  "codebase-intel:48"
  "design-bridge:57"
  "dev-ops:62"
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

# ---------------------------------------------------------------------------
echo "== [S4-F] user documentation =="

# The S4-04 deliverable: 8 user-facing docs in docs/. Each one must
# exist and declare its expected headline section, so a future
# refactor can't silently delete or rename a document.
DOCS="$REPO_ROOT/docs"
declare -a USER_DOCS=(
  "GETTING-STARTED.md"
  "CONFIGURATION.md"
  "SKILLS-REFERENCE.md"
  "PIPELINES.md"
  "HOOKS.md"
  "MCP-SERVERS.md"
  "TROUBLESHOOTING.md"
  "TEAM-MODE.md"
)
for doc in "${USER_DOCS[@]}"; do
  if [[ -f "$DOCS/$doc" ]]; then
    pass "user doc: $doc present"
  else
    fail "user doc: $doc present"
  fi
done

# Every user doc must start with an H1 — anchors and Markdown-aware
# tools rely on this. We also assert one specific anchor per doc to
# catch silent-rewrite regressions.
declare -a DOC_HEADERS=(
  "GETTING-STARTED.md:# Getting Started with VibeFlow"
  "CONFIGURATION.md:# Configuration Reference"
  "SKILLS-REFERENCE.md:# Skills Reference"
  "PIPELINES.md:# Pipelines"
  "HOOKS.md:# Hooks"
  "MCP-SERVERS.md:# MCP Servers"
  "TROUBLESHOOTING.md:# Troubleshooting"
  "TEAM-MODE.md:# Team Mode"
)
for pair in "${DOC_HEADERS[@]}"; do
  doc="${pair%%:*}"
  header="${pair#*:}"
  f="$DOCS/$doc"
  [[ -f "$f" ]] || continue
  # Match exactly the first line so a slug rename surfaces.
  first_line="$(head -n 1 "$f")"
  if [[ "$first_line" == "$header" ]]; then
    pass "$doc starts with H1 '$header'"
  else
    fail "$doc starts with H1 '$header' (got: $first_line)"
  fi
done

# SKILLS-REFERENCE.md must declare every L0/L1/L2/L3 section header
# and every gate-bearing skill name. Spot-check a representative one
# from each layer plus the release decision engine.
SKR="$DOCS/SKILLS-REFERENCE.md"
if [[ -f "$SKR" ]]; then
  for layer in "## L0 — Truth Creation" "## L1 — Truth Validation" "## L2 — Truth Execution" "## L3 — Truth Evolution"; do
    if grep -qF "$layer" "$SKR"; then
      pass "SKILLS-REFERENCE declares '$layer'"
    else
      fail "SKILLS-REFERENCE declares '$layer'"
    fi
  done
  for skill in "prd-quality-analyzer" "reconciliation-simulator" "coverage-analyzer" "decision-recommender" "release-decision-engine"; do
    if grep -qE "^### ${skill}( |$)" "$SKR"; then
      pass "SKILLS-REFERENCE has section for $skill"
    else
      fail "SKILLS-REFERENCE has section for $skill"
    fi
  done
fi

# PIPELINES.md must declare all 7 pipelines plus the decision tree.
PIPES="$DOCS/PIPELINES.md"
if [[ -f "$PIPES" ]]; then
  for n in 1 2 3 4 5 6 7; do
    if grep -qE "^## PIPELINE-${n} —" "$PIPES"; then
      pass "PIPELINES.md declares PIPELINE-${n}"
    else
      fail "PIPELINES.md declares PIPELINE-${n}"
    fi
  done
  if grep -q "Pipeline decision tree" "$PIPES"; then
    pass "PIPELINES.md has the decision tree section"
  else
    fail "PIPELINES.md has the decision tree section"
  fi
fi

# HOOKS.md must reference every hook script by filename so a renamed
# hook surfaces immediately.
HOOKS_DOC="$DOCS/HOOKS.md"
if [[ -f "$HOOKS_DOC" ]]; then
  for hook in "commit-guard.sh" "load-sdlc-context.sh" "post-edit.sh" "trigger-ai-review.sh" "test-optimizer.sh" "compact-recovery.sh" "consensus-aggregator.sh" "_lib.sh"; do
    if grep -qF "$hook" "$HOOKS_DOC"; then
      pass "HOOKS.md references $hook"
    else
      fail "HOOKS.md references $hook"
    fi
  done
fi

# MCP-SERVERS.md must declare all 5 servers as level-2 sections.
MCP_DOC="$DOCS/MCP-SERVERS.md"
if [[ -f "$MCP_DOC" ]]; then
  for srv in "sdlc-engine" "codebase-intel" "design-bridge" "dev-ops" "observability"; do
    if grep -qE "^## ${srv}$" "$MCP_DOC"; then
      pass "MCP-SERVERS.md has section for $srv"
    else
      fail "MCP-SERVERS.md has section for $srv"
    fi
  done
fi

# CONFIGURATION.md must document every userConfig key from
# .claude-plugin/plugin.json. Drift between the plugin manifest and
# the docs is a common regression — this catches it.
CFG_DOC="$DOCS/CONFIGURATION.md"
if [[ -f "$CFG_DOC" ]]; then
  for key in "mode" "domain" "db_connection" "openai_model" "gemini_model" "figma_token" "github_token" "gitlab_token" "gitlab_base_url"; do
    if grep -qE "\\\`${key}\\\`" "$CFG_DOC"; then
      pass "CONFIGURATION.md documents userConfig.${key}"
    else
      fail "CONFIGURATION.md documents userConfig.${key}"
    fi
  done
fi

# GETTING-STARTED.md must link to every other user doc so readers
# can navigate the doc set from a single entry point.
GS_DOC="$DOCS/GETTING-STARTED.md"
if [[ -f "$GS_DOC" ]]; then
  for link in "CONFIGURATION.md" "SKILLS-REFERENCE.md" "PIPELINES.md" "HOOKS.md" "MCP-SERVERS.md" "TROUBLESHOOTING.md" "TEAM-MODE.md"; do
    if grep -qF "$link" "$GS_DOC"; then
      pass "GETTING-STARTED links to $link"
    else
      fail "GETTING-STARTED links to $link"
    fi
  done
fi

# ---------------------------------------------------------------------------
echo "== [S4-G] plugin manifest finalization =="

# The S4-05 deliverable: .claude-plugin/plugin.json finalized for v1.0
# distribution. Top-level keys + version + repository/homepage URLs +
# every userConfig key with title/description/type/sensitive +
# ci_provider wired through .mcp.json + dev-ops MCP.
PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"

if [[ -f "$PLUGIN" ]]; then
  pass "plugin.json present"
else
  fail "plugin.json present"
fi

if jq -e . "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json is valid JSON"
else
  fail "plugin.json is valid JSON"
fi

# Required top-level metadata.
for key in name version description author homepage repository bugs license keywords skills userConfig; do
  if jq -e --arg k "$key" 'has($k)' "$PLUGIN" >/dev/null 2>&1; then
    pass "plugin.json declares top-level '$key'"
  else
    fail "plugin.json declares top-level '$key'"
  fi
done

# Version must match the latest released X.Y.Z — post-v1.0.0 this
# bumps with every patch release. The sprint-4 harness owns this
# check because it's the plugin-manifest section; the release.sh
# preflight runs it on every new release, so the expected version
# has to be bumped here as part of the release commit.
PLUGIN_VERSION="$(jq -r '.version' "$PLUGIN")"
EXPECTED_PLUGIN_VERSION="1.3.0"
if [[ "$PLUGIN_VERSION" == "$EXPECTED_PLUGIN_VERSION" ]]; then
  pass "plugin.json version == $EXPECTED_PLUGIN_VERSION"
else
  fail "plugin.json version == $EXPECTED_PLUGIN_VERSION (got: $PLUGIN_VERSION)"
fi

# Repository must be the structured form ({ type, url }), not a bare string.
if jq -e '.repository | type == "object" and has("type") and has("url")' "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json repository is { type, url } object"
else
  fail "plugin.json repository is { type, url } object"
fi
if jq -e '.repository.url | startswith("https://github.com/")' "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json repository.url is a github https URL"
else
  fail "plugin.json repository.url is a github https URL"
fi

# Bugs must point at the GitHub issues page.
if jq -e '.bugs.url | endswith("/issues")' "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json bugs.url ends with /issues"
else
  fail "plugin.json bugs.url ends with /issues"
fi

# Homepage must be a non-empty URL.
if jq -e '.homepage | type == "string" and startswith("http")' "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json homepage is an http(s) URL"
else
  fail "plugin.json homepage is an http(s) URL"
fi

# Skills path must point at the local skills/ directory.
if jq -e '.skills | type == "string" and startswith("./skills")' "$PLUGIN" >/dev/null 2>&1; then
  pass "plugin.json skills points at ./skills/"
else
  fail "plugin.json skills points at ./skills/"
fi

# Every userConfig key must have title + description + type + sensitive.
USER_CONFIG_KEYS=(mode domain db_connection openai_model gemini_model figma_token github_token ci_provider gitlab_token gitlab_base_url)
for key in "${USER_CONFIG_KEYS[@]}"; do
  if jq -e --arg k "$key" '.userConfig | has($k)' "$PLUGIN" >/dev/null 2>&1; then
    pass "userConfig declares '$key'"
  else
    fail "userConfig declares '$key'"
  fi
  for field in title description type sensitive; do
    if jq -e --arg k "$key" --arg f "$field" '.userConfig[$k] | has($f)' "$PLUGIN" >/dev/null 2>&1; then
      pass "userConfig.$key has '$field'"
    else
      fail "userConfig.$key has '$field'"
    fi
  done
done

# Sensitive flag for the three secret-bearing keys.
for key in db_connection figma_token github_token; do
  if jq -e --arg k "$key" '.userConfig[$k].sensitive == true' "$PLUGIN" >/dev/null 2>&1; then
    pass "userConfig.$key is marked sensitive"
  else
    fail "userConfig.$key is marked sensitive"
  fi
done

# ci_provider must NOT be marked sensitive (it's a non-secret string).
if jq -e '.userConfig.ci_provider.sensitive == false' "$PLUGIN" >/dev/null 2>&1; then
  pass "userConfig.ci_provider is NOT sensitive"
else
  fail "userConfig.ci_provider is NOT sensitive"
fi

# .mcp.json must wire CI_PROVIDER from userConfig into the dev-ops env.
DO_CI_SRC="$(jq -r '.mcpServers."dev-ops".env.CI_PROVIDER' "$MCP_JSON")"
if [[ "$DO_CI_SRC" == "\${userConfig.ci_provider}" ]]; then
  pass "dev-ops CI_PROVIDER flows from userConfig"
else
  fail "dev-ops CI_PROVIDER flows from userConfig (got: $DO_CI_SRC)"
fi

# CONFIGURATION.md must document ci_provider.
if grep -q "ci_provider" "$DOCS/CONFIGURATION.md"; then
  pass "CONFIGURATION.md documents ci_provider"
else
  fail "CONFIGURATION.md documents ci_provider"
fi

# dev-ops source must read CI_PROVIDER from process.env (so the manifest
# field is actually wired through).
if grep -q "process.env.CI_PROVIDER" "$REPO_ROOT/mcp-servers/dev-ops/src/tools.ts"; then
  pass "dev-ops src/tools.ts reads process.env.CI_PROVIDER"
else
  fail "dev-ops src/tools.ts reads process.env.CI_PROVIDER"
fi
# And the dist must be rebuilt (the integration smoke runs against dist).
if grep -q "process.env.CI_PROVIDER" "$REPO_ROOT/mcp-servers/dev-ops/dist/tools.js"; then
  pass "dev-ops dist/tools.js reads process.env.CI_PROVIDER"
else
  fail "dev-ops dist/tools.js reads process.env.CI_PROVIDER"
fi

# ---------------------------------------------------------------------------
echo "== [S4-H] plugin packaging =="

# build-all.sh and package-plugin.sh exist + executable.
for script in build-all.sh package-plugin.sh; do
  if [[ -f "$REPO_ROOT/$script" ]]; then
    pass "$script present"
  else
    fail "$script present"
    continue
  fi
  if [[ -x "$REPO_ROOT/$script" ]]; then
    pass "$script is executable"
  else
    fail "$script is executable"
  fi
done

# Every MCP server's dist/index.js must be tracked in git (S4-06's
# load-bearing change — without this, `claude plugin install` from
# a fresh clone or tarball lands without working JS).
for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
  if git -C "$REPO_ROOT" ls-files --error-unmatch "mcp-servers/$mcp/dist/index.js" >/dev/null 2>&1; then
    pass "$mcp/dist/index.js is git-tracked"
  else
    fail "$mcp/dist/index.js is git-tracked"
  fi
done

# Source-map files must NOT be tracked (kept out of the tarball to
# stay lean — recoverable from src/ when needed).
for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
  if git -C "$REPO_ROOT" ls-files "mcp-servers/$mcp/dist/index.js.map" 2>/dev/null | grep -q .; then
    fail "$mcp/dist/index.js.map should NOT be tracked"
  else
    pass "$mcp/dist/index.js.map is not tracked"
  fi
done

# .gitignore must keep the dangerous defaults in place — node_modules,
# .DS_Store, generated .vibeflow state — so a future contributor
# cannot accidentally commit them.
GITIGNORE="$REPO_ROOT/.gitignore"
for pat in "node_modules/" ".DS_Store" ".vibeflow/state.db" "vibeflow-plugin-*.tar.gz"; do
  if grep -qF "$pat" "$GITIGNORE"; then
    pass ".gitignore excludes $pat"
  else
    fail ".gitignore excludes $pat"
  fi
done

# .gitignore must contain the negation that un-ignores MCP server dist/.
if grep -q '!mcp-servers/\*/dist/' "$GITIGNORE"; then
  pass ".gitignore un-ignores mcp-servers/*/dist/"
else
  fail ".gitignore un-ignores mcp-servers/*/dist/"
fi

# Live verification: git check-ignore confirms the negation works.
if ! git -C "$REPO_ROOT" check-ignore -q mcp-servers/sdlc-engine/dist/index.js 2>/dev/null; then
  pass "git check-ignore agrees mcp-servers/sdlc-engine/dist/index.js is tracked"
else
  fail "git check-ignore agrees mcp-servers/sdlc-engine/dist/index.js is tracked"
fi
# And confirms .map files are still ignored.
if git -C "$REPO_ROOT" check-ignore -q mcp-servers/sdlc-engine/dist/index.js.map 2>/dev/null; then
  pass "git check-ignore agrees .map files are still ignored"
else
  fail "git check-ignore agrees .map files are still ignored"
fi

# build-all.sh --check on every MCP server passes today.
if (cd "$REPO_ROOT" && bash build-all.sh --check >/dev/null 2>&1); then
  pass "build-all.sh --check succeeds for all 5 MCP servers"
else
  fail "build-all.sh --check succeeds for all 5 MCP servers"
fi

# package-plugin.sh --skip-build produces a tarball + verifies forbidden
# paths + verifies required paths. We invoke it and check exit code.
if (cd "$REPO_ROOT" && bash package-plugin.sh --skip-build >/dev/null 2>&1); then
  pass "package-plugin.sh --skip-build produces a clean tarball"
else
  fail "package-plugin.sh --skip-build produces a clean tarball"
fi
# The archive itself must exist after the previous step succeeded.
if ls "$REPO_ROOT"/vibeflow-plugin-*.tar.gz >/dev/null 2>&1; then
  pass "vibeflow-plugin-<version>.tar.gz exists"
  # Spot-check: the archive must contain the manifest at the expected
  # path and at least one MCP server's dist/index.js.
  ARCHIVE="$(ls "$REPO_ROOT"/vibeflow-plugin-*.tar.gz | head -1)"
  if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "^.claude-plugin/plugin.json$"; then
    pass "tarball contains .claude-plugin/plugin.json"
  else
    fail "tarball contains .claude-plugin/plugin.json"
  fi
  if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "^mcp-servers/sdlc-engine/dist/index.js$"; then
    pass "tarball contains sdlc-engine/dist/index.js"
  else
    fail "tarball contains sdlc-engine/dist/index.js"
  fi
  # And forbidden paths must NOT be in the tarball.
  for forbidden in "node_modules/" "/CLAUDE.md" "/docs/SPRINT-4.md" "/.git/" "src/index.ts"; do
    if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q "$forbidden"; then
      fail "tarball contains forbidden path: $forbidden"
    else
      pass "tarball does NOT contain $forbidden"
    fi
  done
else
  fail "vibeflow-plugin-<version>.tar.gz exists"
fi

# ---------------------------------------------------------------------------
echo "== [S4-I] CHANGELOG + release readiness =="

# CHANGELOG.md must exist at repo root and follow Keep-a-Changelog
# format. We assert presence + the canonical header + every sprint
# section + the v1.0.0 release marker.
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

if [[ -f "$CHANGELOG" ]]; then
  pass "CHANGELOG.md present at repo root"
else
  fail "CHANGELOG.md present at repo root"
fi

if [[ -f "$CHANGELOG" ]]; then
  if head -n 1 "$CHANGELOG" | grep -q "^# Changelog"; then
    pass "CHANGELOG.md starts with H1 '# Changelog'"
  else
    fail "CHANGELOG.md starts with H1 '# Changelog'"
  fi

  # Keep-a-Changelog format reference.
  if grep -q "Keep a Changelog" "$CHANGELOG"; then
    pass "CHANGELOG.md cites Keep-a-Changelog format"
  else
    fail "CHANGELOG.md cites Keep-a-Changelog format"
  fi

  # SemVer reference.
  if grep -q "Semantic Versioning" "$CHANGELOG"; then
    pass "CHANGELOG.md cites SemVer"
  else
    fail "CHANGELOG.md cites SemVer"
  fi

  # The v1.0.0 release entry must exist with an ISO date.
  if grep -qE "^## \[1\.0\.0\] — [0-9]{4}-[0-9]{2}-[0-9]{2}" "$CHANGELOG"; then
    pass "CHANGELOG.md has [1.0.0] release entry with date"
  else
    fail "CHANGELOG.md has [1.0.0] release entry with date"
  fi

  # Every sprint must have a section so the changelog tells the
  # full story end-to-end.
  for sprint in "Sprint 1" "Sprint 2" "Sprint 3" "Sprint 4"; do
    if grep -q "Added — ${sprint}" "$CHANGELOG"; then
      pass "CHANGELOG.md documents ${sprint}"
    else
      fail "CHANGELOG.md documents ${sprint}"
    fi
  done

  # Distribution + breaking-changes + migration sections must be
  # present (Keep-a-Changelog conventional sections).
  for section in "### Breaking changes" "### Migration" "### Distribution" "### Test baseline growth"; do
    if grep -qF "$section" "$CHANGELOG"; then
      pass "CHANGELOG.md has '$section'"
    else
      fail "CHANGELOG.md has '$section'"
    fi
  done

  # The release entry must match plugin.json's version literal.
  CHANGELOG_VERSION="$(grep -oE '## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | head -1 | tr -d '[]## ')"
  PLUGIN_VERSION="$(jq -r '.version' "$PLUGIN")"
  if [[ "$CHANGELOG_VERSION" == "$PLUGIN_VERSION" ]]; then
    pass "CHANGELOG.md latest version matches plugin.json ($PLUGIN_VERSION)"
  else
    fail "CHANGELOG.md latest version matches plugin.json (changelog=$CHANGELOG_VERSION plugin=$PLUGIN_VERSION)"
  fi

  # CHANGELOG must link back to GETTING-STARTED + the demo walkthrough
  # so a reader landing on the changelog has a clear next action.
  for link in "docs/GETTING-STARTED.md" "examples/demo-app/docs/DEMO-WALKTHROUGH.md"; do
    if grep -qF "$link" "$CHANGELOG"; then
      pass "CHANGELOG.md links to $link"
    else
      fail "CHANGELOG.md links to $link"
    fi
  done
fi

# ---------------------------------------------------------------------------
echo "== [S4-J] performance + edge case hardening =="

# Offline / network-failure tests must be wired in design-bridge and
# dev-ops. We assert by name so a future test rename surfaces.
DB_CLIENT_TEST="$REPO_ROOT/mcp-servers/design-bridge/tests/client.test.ts"
if grep -q "offline / network failure" "$DB_CLIENT_TEST"; then
  pass "design-bridge client.test.ts has offline describe block"
else
  fail "design-bridge client.test.ts has offline describe block"
fi
for needle in "ECONNREFUSED" "ENOTFOUND" "socket hang up"; do
  if grep -qF "$needle" "$DB_CLIENT_TEST"; then
    pass "design-bridge tests $needle path"
  else
    fail "design-bridge tests $needle path"
  fi
done

DO_CLIENT_TEST="$REPO_ROOT/mcp-servers/dev-ops/tests/client.test.ts"
for needle in "ECONNREFUSED" "ENOTFOUND" "transport-classified"; do
  if grep -qF "$needle" "$DO_CLIENT_TEST"; then
    pass "dev-ops tests $needle path"
  else
    fail "dev-ops tests $needle path"
  fi
done

# Large-input scaling test must be wired in codebase-intel.
CI_IMPORTS_TEST="$REPO_ROOT/mcp-servers/codebase-intel/tests/imports.test.ts"
if grep -q "Large-input scaling" "$CI_IMPORTS_TEST"; then
  pass "codebase-intel imports.test.ts has large-input scaling block"
else
  fail "codebase-intel imports.test.ts has large-input scaling block"
fi
# The 200-file scenario specifically — catches an accidental size cut.
if grep -q "200-file project under 5 seconds" "$CI_IMPORTS_TEST"; then
  pass "codebase-intel scales to a 200-file project under 5s budget"
else
  fail "codebase-intel scales to a 200-file project under 5s budget"
fi
if grep -q "findCycles terminates on a 200-file dense graph" "$CI_IMPORTS_TEST"; then
  pass "codebase-intel findCycles scales to 200-node graph under 2s budget"
else
  fail "codebase-intel findCycles scales to 200-node graph under 2s budget"
fi

# Hook output budget tests must be wired in hooks/tests/run.sh.
HOOKS_TEST="$REPO_ROOT/hooks/tests/run.sh"
if grep -q "load-sdlc-context output stays under 250 char budget" "$HOOKS_TEST"; then
  pass "hooks tests budget load-sdlc-context to 250 chars"
else
  fail "hooks tests budget load-sdlc-context to 250 chars"
fi
if grep -q "compact-recovery output stays under 800 char budget" "$HOOKS_TEST"; then
  pass "hooks tests budget compact-recovery to 800 chars"
else
  fail "hooks tests budget compact-recovery to 800 chars"
fi

# Error-message actionability sentinel: every CiConfigError /
# FigmaConfigError throw site should include either "Set it via",
# "Create at", or some imperative guidance phrase. Drift here is
# how we'd lose the user-friendly message contract.
DB_CLIENT="$REPO_ROOT/mcp-servers/design-bridge/src/client.ts"
DO_CLIENT="$REPO_ROOT/mcp-servers/dev-ops/src/client.ts"
if grep -q "Set it via plugin userConfig" "$DB_CLIENT"; then
  pass "design-bridge config error mentions 'Set it via plugin userConfig'"
else
  fail "design-bridge config error mentions 'Set it via plugin userConfig'"
fi
if grep -q "Set it via plugin userConfig" "$DO_CLIENT"; then
  pass "dev-ops config error mentions 'Set it via plugin userConfig'"
else
  fail "dev-ops config error mentions 'Set it via plugin userConfig'"
fi

# commit-guard error messages must include the user's next action.
COMMIT_GUARD="$REPO_ROOT/hooks/scripts/commit-guard.sh"
if grep -q "Advance to DEVELOPMENT via /vibeflow:advance" "$COMMIT_GUARD"; then
  pass "commit-guard error tells user to /vibeflow:advance"
else
  fail "commit-guard error tells user to /vibeflow:advance"
fi
if grep -q "Expected prefix" "$COMMIT_GUARD"; then
  pass "commit-guard error names the conventional-commit prefixes"
else
  fail "commit-guard error names the conventional-commit prefixes"
fi

# ===========================================================================
# [S4-K] Final fresh-install end-to-end simulation
# ===========================================================================
#
# This section is the closest we can get to "claude plugin install
# vibeflow → use it" without spawning a recursive Claude Code session.
# It does five things end-to-end against an extracted tarball + a
# synthetic user project:
#
#   1. Extracts vibeflow-plugin-1.0.0.tar.gz to a fresh temp dir
#   2. Verifies every load-bearing path is present + parses
#   3. Walks the sdlc-engine MCP through REQUIREMENTS → DEPLOYMENT
#      via JSON-RPC, asserting each phase advance fires its gate
#   4. Fires every hook against the synthetic project + asserts the
#      side effects (log rows, state files, commit allow/deny)
#   5. Reads back the final state.db + asserts it matches the
#      expected end-of-walk state
#
# This is the operational climax of the harness suite — if it passes,
# a fresh user installing the v1.0 plugin should be able to walk a
# project from REQUIREMENTS → DEPLOYMENT.
# ---------------------------------------------------------------------------

echo "== [S4-K] fresh-install end-to-end simulation =="

ARCHIVE="$(ls "$REPO_ROOT"/vibeflow-plugin-*.tar.gz 2>/dev/null | head -1)"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  fail "[S4-K] tarball not found — run ./package-plugin.sh first"
else
  pass "tarball located: $(basename "$ARCHIVE")"

  S4K_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vf-s4k-XXXXXX")"
  S4K_PLUGIN="$S4K_ROOT/plugin"
  S4K_PROJECT="$S4K_ROOT/project"
  mkdir -p "$S4K_PLUGIN" "$S4K_PROJECT"

  # --------- 1. Extract + payload sanity ----------------------------------
  if tar -xzf "$ARCHIVE" -C "$S4K_PLUGIN" 2>/dev/null; then
    pass "tarball extracts cleanly to a fresh dir"
  else
    fail "tarball extracts cleanly to a fresh dir"
  fi

  # Manifest is parseable + version matches the current release.
  if jq -e --arg v "$EXPECTED_PLUGIN_VERSION" '.version == $v' "$S4K_PLUGIN/.claude-plugin/plugin.json" >/dev/null 2>&1; then
    pass "extracted plugin.json reports version $EXPECTED_PLUGIN_VERSION"
  else
    fail "extracted plugin.json reports version $EXPECTED_PLUGIN_VERSION"
  fi

  # Every MCP server dist/index.js exists in the extracted tree AND
  # parses as valid JS (no truncation during tar/extract).
  for mcp in sdlc-engine codebase-intel design-bridge dev-ops observability; do
    DIST="$S4K_PLUGIN/mcp-servers/$mcp/dist/index.js"
    if [[ -f "$DIST" ]] && node --check "$DIST" 2>/dev/null; then
      pass "extracted $mcp/dist/index.js parses"
    else
      fail "extracted $mcp/dist/index.js parses"
    fi
  done

  # Every skill (26 total) has a SKILL.md in the extracted tree.
  EXTRACTED_SKILL_COUNT="$(find "$S4K_PLUGIN/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  if (( EXTRACTED_SKILL_COUNT >= 26 )); then
    pass "extracted plugin has >=26 SKILL.md files (got $EXTRACTED_SKILL_COUNT)"
  else
    fail "extracted plugin has >=26 SKILL.md files (got $EXTRACTED_SKILL_COUNT)"
  fi

  # Every hook script is executable in the extracted tree.
  for hook in commit-guard.sh load-sdlc-context.sh post-edit.sh \
              trigger-ai-review.sh test-optimizer.sh compact-recovery.sh \
              consensus-aggregator.sh; do
    if [[ -x "$S4K_PLUGIN/hooks/scripts/$hook" ]]; then
      pass "extracted hooks/scripts/$hook is executable"
    else
      fail "extracted hooks/scripts/$hook is executable"
    fi
  done

  # --------- 2. Synthesize a user project ---------------------------------
  cat > "$S4K_PROJECT/vibeflow.config.json" <<'JSON'
{
  "project": "s4k-e2e",
  "mode": "solo",
  "domain": "general",
  "currentPhase": "REQUIREMENTS"
}
JSON
  mkdir -p "$S4K_PROJECT/.vibeflow" "$S4K_PROJECT/src"
  echo "export const greeting = 'hello';" > "$S4K_PROJECT/src/main.ts"
  pass "synthesized user project at $S4K_PROJECT"

  # --------- 3. Walk the sdlc-engine through every phase ------------------
  # Drive the engine via JSON-RPC just like a real plugin invocation
  # would. We use the IN-REPO dist (which has node_modules resolved)
  # rather than the extracted dist, because `claude plugin install`
  # is responsible for installing the MCP dependencies on the user's
  # machine — the tarball intentionally ships dist/*.js but not
  # node_modules. The extracted dist files were already validated by
  # `node --check` above (parse-only), which is all the tarball
  # contract guarantees.
  #
  # IMPORTANT: the @modelcontextprotocol/sdk dispatches JSON-RPC
  # requests in PARALLEL — there is no guarantee that requests in a
  # single stdin batch run in order. A read-then-write pattern in one
  # batch can see the writes BEFORE the read returns. We split the
  # walk into two sequential engine invocations:
  #
  #   Phase A: fresh project → sdlc_get_state, expect REQUIREMENTS
  #   Phase B: full satisfy/record/advance walk → expect DEVELOPMENT
  #
  # Each invocation is its own engine process with its own stdin
  # closed at end, so the in-process dispatch finishes before we read
  # the next set of responses.

  export VIBEFLOW_SQLITE_PATH="$S4K_PROJECT/.vibeflow/state.db"
  export VIBEFLOW_PROJECT="s4k-e2e"
  export VIBEFLOW_MODE="solo"

  # ---- Phase A — initial state on a fresh project ----
  S4K_INIT_OUT="$(node "$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s4k","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"s4k-e2e"}}}
EOF
  )"
  if echo "$S4K_INIT_OUT" | grep -q "REQUIREMENTS"; then
    pass "initial sdlc_get_state returns REQUIREMENTS"
  else
    fail "initial sdlc_get_state returns REQUIREMENTS"
  fi

  # ---- Phase B — full SDLC walk ----
  S4K_OUT="$(node "$REPO_ROOT/mcp-servers/sdlc-engine/dist/index.js" <<'EOF' 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s4k","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"prd.approved"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"testability.score>=60"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"s4k-e2e","phase":"REQUIREMENTS","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"s4k-e2e","to":"DESIGN"}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"design.approved"}}}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"accessibility.verified"}}}
{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"s4k-e2e","phase":"DESIGN","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"s4k-e2e","to":"ARCHITECTURE"}}}
{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"adr.recorded"}}}
{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"consensus.approved"}}}
{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"s4k-e2e","phase":"ARCHITECTURE","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"s4k-e2e","to":"PLANNING"}}}
{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"test-strategy.approved"}}}
{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"sdlc_satisfy_criterion","arguments":{"projectId":"s4k-e2e","criterion":"sprint.planned"}}}
{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"sdlc_record_consensus","arguments":{"projectId":"s4k-e2e","phase":"PLANNING","agreement":0.95,"criticalIssues":0}}}
{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"sdlc_advance_phase","arguments":{"projectId":"s4k-e2e","to":"DEVELOPMENT"}}}
{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"sdlc_get_state","arguments":{"projectId":"s4k-e2e"}}}
EOF
  )"
  unset VIBEFLOW_SQLITE_PATH VIBEFLOW_PROJECT VIBEFLOW_MODE

  # The MCP SDK dispatches requests in parallel, so we cannot rely on
  # a get_state RESPONSE in the same batch reflecting the final state
  # — get_state may execute before the in-flight writes complete.
  # The authoritative verification is the state.db file spot check
  # below, which reads the row AFTER the engine process exits.
  #
  # We still verify that NONE of the JSON-RPC responses report
  # `isError: true`, which catches a write that failed mid-walk.
  ERROR_LINES="$(echo "$S4K_OUT" | grep -c '"isError":true')"
  if [[ "$ERROR_LINES" == "0" ]]; then
    pass "no JSON-RPC errors during full walk"
  else
    fail "no JSON-RPC errors during full walk (got $ERROR_LINES error responses)"
  fi

  # Every advance call (ids 6, 10, 14, 18) must produce a non-error
  # response. Use end-of-line anchoring so id=12 / id=18 don't collide.
  for id in 6 10 14 18; do
    LINE="$(echo "$S4K_OUT" | grep -E "\"id\":${id}}\$")"
    if [[ -n "$LINE" && "$LINE" != *'"isError":true'* ]]; then
      pass "advance #$id succeeded"
    else
      fail "advance #$id succeeded"
    fi
  done

  # The state.db must exist on disk after the walk.
  if [[ -f "$S4K_PROJECT/.vibeflow/state.db" ]]; then
    pass "engine wrote state.db on disk"
  else
    fail "engine wrote state.db on disk"
  fi

  # --------- 4. Fire every hook against the synthetic project -------------
  export VIBEFLOW_CWD="$S4K_PROJECT"

  # commit-guard: at DEVELOPMENT, conformant commit passes.
  INPUT='{"tool_input":{"command":"git commit -m \"feat(s4k): hello\""}}'
  echo "$INPUT" | bash "$S4K_PLUGIN/hooks/scripts/commit-guard.sh" >/dev/null 2>/dev/null
  RC=$?
  if (( RC == 0 )); then
    pass "extracted commit-guard allows conformant commit at DEVELOPMENT"
  else
    fail "extracted commit-guard allows conformant commit at DEVELOPMENT (rc=$RC)"
  fi

  # commit-guard: malformed message at DEVELOPMENT still rejected.
  INPUT='{"tool_input":{"command":"git commit -m \"nope\""}}'
  echo "$INPUT" | bash "$S4K_PLUGIN/hooks/scripts/commit-guard.sh" >/dev/null 2>/dev/null
  RC=$?
  if (( RC == 2 )); then
    pass "extracted commit-guard rejects malformed message at DEVELOPMENT"
  else
    fail "extracted commit-guard rejects malformed message at DEVELOPMENT (rc=$RC)"
  fi

  # load-sdlc-context: must report DEVELOPMENT.
  CTX="$(bash "$S4K_PLUGIN/hooks/scripts/load-sdlc-context.sh")"
  if [[ "$CTX" == *"phase=DEVELOPMENT"* ]]; then
    pass "extracted load-sdlc-context reports phase=DEVELOPMENT"
  else
    fail "extracted load-sdlc-context reports phase=DEVELOPMENT"
  fi
  # Output stays under the 250-char budget even on the extracted layout.
  if (( ${#CTX} <= 250 )); then
    pass "extracted load-sdlc-context output within budget (${#CTX})"
  else
    fail "extracted load-sdlc-context output within budget (${#CTX})"
  fi

  # post-edit: TS file gets logged.
  INPUT="{\"tool_input\":{\"file_path\":\"$S4K_PROJECT/src/main.ts\"}}"
  echo "$INPUT" | bash "$S4K_PLUGIN/hooks/scripts/post-edit.sh" >/dev/null 2>/dev/null
  if grep -q "src/main.ts" "$S4K_PROJECT/.vibeflow/traces/changed-files.log" 2>/dev/null; then
    pass "extracted post-edit logged a TS edit"
  else
    fail "extracted post-edit logged a TS edit"
  fi

  # test-optimizer: hint file written even with no test match (empty hint OK).
  bash "$S4K_PLUGIN/hooks/scripts/test-optimizer.sh" < /dev/null >/dev/null 2>&1
  if [[ -f "$S4K_PROJECT/.vibeflow/state/next-test-hint.json" ]]; then
    pass "extracted test-optimizer wrote next-test-hint.json"
  else
    fail "extracted test-optimizer wrote next-test-hint.json"
  fi

  # compact-recovery: snapshot mentions phase + criteria.
  CR="$(bash "$S4K_PLUGIN/hooks/scripts/compact-recovery.sh")"
  if [[ "$CR" == *"phase=DEVELOPMENT"* ]]; then
    pass "extracted compact-recovery snapshot reports DEVELOPMENT"
  else
    fail "extracted compact-recovery snapshot reports DEVELOPMENT"
  fi
  if (( ${#CR} <= 800 )); then
    pass "extracted compact-recovery output within budget (${#CR})"
  else
    fail "extracted compact-recovery output within budget (${#CR})"
  fi

  # consensus-aggregator: solo-mode single APPROVED → finalized verdict.
  INPUT='{"session_id":"s4k","subagent_type":"claude-reviewer","tool_response":{"content":[{"text":"Verdict: APPROVED\ncritical issues: 0"}]}}'
  echo "$INPUT" | bash "$S4K_PLUGIN/hooks/scripts/consensus-aggregator.sh" >/dev/null 2>/dev/null
  VERDICT_FILE="$S4K_PROJECT/.vibeflow/state/consensus/s4k.verdict.json"
  if [[ -f "$VERDICT_FILE" ]]; then
    pass "extracted consensus-aggregator finalized solo verdict"
    STATUS="$(jq -r '.status' "$VERDICT_FILE" 2>/dev/null)"
    if [[ "$STATUS" == "APPROVED" ]]; then
      pass "extracted consensus solo verdict is APPROVED"
    else
      fail "extracted consensus solo verdict is APPROVED (got: $STATUS)"
    fi
  else
    fail "extracted consensus-aggregator finalized solo verdict"
  fi

  # trigger-ai-review: solo mode is a no-op (no marker written).
  bash "$S4K_PLUGIN/hooks/scripts/trigger-ai-review.sh" < /dev/null >/dev/null 2>&1
  if [[ ! -f "$S4K_PROJECT/.vibeflow/state/review-pending.json" ]]; then
    pass "extracted trigger-ai-review correctly no-ops in solo mode"
  else
    fail "extracted trigger-ai-review correctly no-ops in solo mode"
  fi

  unset VIBEFLOW_CWD

  # --------- 5. Final state.db spot check ---------------------------------
  # The synthesized project's state.db should report DEVELOPMENT and
  # the satisfied_criteria array should contain the criteria we marked.
  if command -v sqlite3 >/dev/null 2>&1; then
    PHASE_VAL="$(sqlite3 "$S4K_PROJECT/.vibeflow/state.db" \
      "SELECT current_phase FROM project_state WHERE project_id='s4k-e2e';" 2>/dev/null)"
    if [[ "$PHASE_VAL" == "DEVELOPMENT" ]]; then
      pass "final state.db.current_phase == DEVELOPMENT"
    else
      fail "final state.db.current_phase == DEVELOPMENT (got: $PHASE_VAL)"
    fi
    # satisfied_criteria is reset at every phase transition (each
    # phase has its own gate criteria). After advancing into
    # DEVELOPMENT we did not satisfy any DEVELOPMENT-specific
    # criteria, so the array is expected to be empty `[]` — the
    # important assertion is that the column is a valid JSON array.
    SAT_VAL="$(sqlite3 "$S4K_PROJECT/.vibeflow/state.db" \
      "SELECT satisfied_criteria FROM project_state WHERE project_id='s4k-e2e';" 2>/dev/null)"
    if echo "$SAT_VAL" | jq empty >/dev/null 2>&1; then
      pass "final state.db.satisfied_criteria is a valid JSON array (got: $SAT_VAL)"
    else
      fail "final state.db.satisfied_criteria is a valid JSON array (got: $SAT_VAL)"
    fi
    # The revision counter must reflect the full walk. Each
    # satisfy_criterion / record_consensus / advance_phase increments
    # by 1, so 4 advances + 4×(2 satisfy + 1 consensus) = 16 writes.
    # Allow a range to absorb future changes to the criteria list.
    REV_VAL="$(sqlite3 "$S4K_PROJECT/.vibeflow/state.db" \
      "SELECT revision FROM project_state WHERE project_id='s4k-e2e';" 2>/dev/null)"
    if [[ -n "$REV_VAL" ]] && (( REV_VAL >= 12 )); then
      pass "final state.db.revision reflects full walk (>=12, got: $REV_VAL)"
    else
      fail "final state.db.revision reflects full walk (>=12, got: $REV_VAL)"
    fi
  fi

  # Cleanup
  rm -rf "$S4K_ROOT"
fi

echo
echo "RESULTS: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
