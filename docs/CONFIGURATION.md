# Configuration Reference

Everything you can set in VibeFlow, organized by where it lives.

| File | Purpose | Per-project? |
|------|---------|--------------|
| `vibeflow.config.json` | The authoritative project file — one per project | yes |
| `test-strategy.md → crossRunTolerance` / `coverageAnalyzer.weights` / ... | Per-skill gate overrides (tighten-only) | yes |
| `userConfig` (Claude Code settings) | Secrets + per-user preferences | no (per-user) |
| `.mcp.json` | MCP server wiring (plugin-controlled) | no (plugin-controlled) |
| Environment variables | Overrides for hooks + MCP runtime | per-shell |

## 1. `vibeflow.config.json`

This file is created by `/vibeflow:init` in your project root. It is
checked into git. Every hook and skill reads it for context.

### Shape

```json
{
  "project": "my-app",
  "mode": "solo",
  "domain": "e-commerce",
  "currentPhase": "DEVELOPMENT",
  "platform": "web",
  "riskTolerance": "medium",
  "sourceDir": "src/",
  "testDir": "tests/",
  "outputDir": ".vibeflow/",
  "tech": {
    "language": "typescript",
    "runtime": "node",
    "testRunner": "vitest"
  },
  "criticalPaths": [
    "src/payments/",
    "src/auth/"
  ],
  "models": {
    "claude": "claude-sonnet-4-6",
    "openai": "gpt-4o",
    "gemini": "gemini-2.0-flash"
  },
  "defaultPipeline": "new-feature"
}
```

### Fields

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `project` | string | ✓ | — | Stable id used in every report and state record. Do not rename after init. |
| `mode` | `"solo"` / `"team"` | ✓ | `"solo"` | Solo uses SQLite + single-AI reviews; team uses PostgreSQL + 3-AI consensus. |
| `domain` | `"financial"` / `"e-commerce"` / `"healthcare"` / `"general"` | ✓ | `"general"` | Drives quality thresholds + release-decision weights. |
| `currentPhase` | `"REQUIREMENTS"` / `"DESIGN"` / `"ARCHITECTURE"` / `"PLANNING"` / `"DEVELOPMENT"` / `"TESTING"` / `"DEPLOYMENT"` | ✓ | `"REQUIREMENTS"` | Authoritative phase — state.db is the real source of truth; this field is a fallback. |
| `platform` | `"web"` / `"ios"` / `"android"` / `"all"` | — | `"web"` | Affects test file shape + e2e-test-writer output. |
| `riskTolerance` | `"low"` / `"medium"` / `"high"` | — | `"medium"` | Fed into release-decision-engine's CONDITIONAL-band logic. |
| `sourceDir` | string (relative path) | — | `"src/"` | Scanned by coverage-analyzer + test-priority-engine. |
| `testDir` | string (relative path) | — | `"tests/"` | Where generated tests land. |
| `outputDir` | string (relative path) | — | `".vibeflow/"` | Root for reports/artifacts/traces. |
| `tech.language` | string | — | auto | Detected by codebase-intel on init. |
| `tech.runtime` | string | — | auto | e.g. `"node"`, `"python"`, `"java"`. |
| `tech.testRunner` | string | — | auto | e.g. `"vitest"`, `"jest"`, `"pytest"`. |
| `criticalPaths` | string[] | — | `[]` | File or directory globs marked as critical. Coverage-analyzer enforces 100% on these; mutation-test-runner weights them 2×. |
| `models.claude` / `.openai` / `.gemini` | string | — | per-mode defaults | Model ids passed to the consensus orchestrator. |
| `defaultPipeline` | `"new-feature"` / `"pre-pr"` / `"staging-uat"` / `"release"` / `"hotfix"` / `"weekly-learning"` / `"production-feedback"` | — | `"new-feature"` | The pipeline `/vibeflow:run-pipeline` defaults to. |

### Domain → thresholds (built-in, cannot be loosened)

| Domain | GO ≥ | CONDITIONAL ≥ | Load-bearing weights |
|--------|------|---------------|----------------------|
| `financial` | 90 | 75 | invariants 25%, uat 15%, coverage 15% |
| `healthcare` | 95 | 85 | coverage 30%, contract 20%, uat 15% |
| `e-commerce` | 85 | 70 | uat 25%, coverage 15%, visual 15% |
| `general` | 80 | 65 | coverage 20%, tests 20%, uat 15% |

Domain thresholds can be **tightened** via `test-strategy.md`
overrides (e.g. `financial: 0.99` is legal, `financial: 0.85` is
rejected at config load). Same rule applies to every other gate in
VibeFlow: thresholds only move stricter, never looser.

## 2. Per-skill overrides in `test-strategy.md`

Skills that have gate weights or tolerances read their overrides from
`test-strategy.md` at the project root, if present. Every override
follows three rules:

1. **Tighten only** — a weight or threshold can be made stricter,
   never looser. Config load rejects any override that would weaken
   a gate.
2. **Retrospective required** — changing a default requires a
   retrospective on ≥10 real runs showing the new value catches
   issues the default missed. The skill's reference file documents
   this discipline.
3. **Version bump** — overrides record the current version of the
   skill's config (e.g. `coverageAnalyzerVersion: 1`,
   `toleranceConfigVersion: 1`, `ledgerInvariantsVersion: 1`) and
   fail loud if that version doesn't match.

Example — tightening cross-run consistency for a financial project:

```yaml
# test-strategy.md
crossRunTolerance:
  defaults:
    strict: true
    numericRelative: 0.005         # tighter than default 0.02
    pixelDiff: 0.001               # tighter than default 0.01
  domainOverride:
    financial: 0.99                # tighter than default 0.98

coverageAnalyzer:
  weights:
    priority: 0.45                 # tighter than default 0.40
    criticality: 0.35              # tighter than default 0.30
    churn: 0.15                    # tighter than default 0.20
    requirementLink: 0.05          # tighter than default 0.10
```

See each skill's `references/*.md` for its exact override shape and
version. The canonical list is in
[docs/SKILLS-REFERENCE.md](./SKILLS-REFERENCE.md).

## 3. `userConfig` (Claude Code settings)

Claude Code stores per-user values declared by the plugin in
`.claude-plugin/plugin.json → userConfig`. These are **not** checked
into your project — they live in your local Claude Code settings
and are typically secrets or personal preferences.

| Key | Sensitive | Purpose |
|-----|-----------|---------|
| `mode` | no | Override project-level mode for your own sessions (rarely needed) |
| `domain` | no | Same, for domain |
| `db_connection` | **yes** | PostgreSQL DSN for team-mode projects. Leave empty in solo mode. |
| `openai_model` | no | OpenAI model id used by `codex` CLI during consensus review. Empty disables ChatGPT reviews. |
| `gemini_model` | no | Google model id used by `gemini` CLI during consensus review. Empty disables Gemini reviews. |
| `figma_token` | **yes** | Figma personal access token for `design-bridge`. Create at figma.com → Settings → Personal access tokens. Empty disables Figma-dependent skills. |
| `github_token` | **yes** | GitHub PAT for `dev-ops`. Needs `actions:write` + `contents:read` minimum. Empty disables CI-dependent skills. |
| `ci_provider` | no | Which CI/CD system the `dev-ops` MCP targets: `"github"` (default — GitHub Actions via the `createGithubClient`) or `"gitlab"` (GitLab CI via the `createGitlabClient`, added in v1.0.1 / Sprint 5 / S5-02). Unknown values raise a loud `CiConfigError` at first call. For GitLab, the `owner`/`repo` tool arguments are collapsed into the GitLab "namespace/name" project path. |

Set these via Claude Code's plugin settings UI, NOT by editing
`.claude-plugin/plugin.json` by hand — that file is plugin source.

## 4. `.mcp.json` (plugin-controlled)

This file wires the 5 MCP servers into Claude Code. You should not
edit it by hand — the plugin owns it. It references user config via
`${userConfig.figma_token}` / `${userConfig.github_token}` template
strings so secrets flow from your Claude Code settings into the MCP
environment without being written to disk in plaintext.

If a future refactor accidentally inlines a token, the integration
harness's `run.sh [3]` section (`design-bridge FIGMA_TOKEN flows from
userConfig` / `dev-ops GITHUB_TOKEN flows from userConfig`) fails
fast. This is the Bug #7 regression guard.

## 5. Environment variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `VIBEFLOW_CWD` | every hook | Override the working directory (tests + CI pin this to a temp project) |
| `VIBEFLOW_SQLITE_PATH` | sdlc-engine MCP | Point at a non-default SQLite file (default: `<cwd>/.vibeflow/state.db`) |
| `VIBEFLOW_PROJECT` | sdlc-engine MCP | Override `project` id for a single session |
| `VIBEFLOW_MODE` | sdlc-engine MCP | Override `mode` for a single session |
| `FIGMA_TOKEN` | design-bridge MCP | Populated from `userConfig.figma_token` |
| `GITHUB_TOKEN` | dev-ops MCP | Populated from `userConfig.github_token` |
| `CI_PROVIDER` | dev-ops MCP | Populated from `userConfig.ci_provider`. Defaults to `github` when unset. |

Environment variables override `vibeflow.config.json` values when
both are set. Use this only for one-off diagnostic runs — persistent
overrides belong in the config file.

## 6. `criticalPaths` — why this matters

Every gating skill reads `criticalPaths` from your config and applies
stricter rules to those files:

- **coverage-analyzer** — enforces 100% line + branch coverage on
  every file in `criticalPaths`; non-critical files only need to
  meet the domain threshold
- **mutation-test-runner** — weights surviving mutants in
  `criticalPaths` 2× in the aggregate score; zero surviving P0
  mutants in critical code is a hard block
- **test-priority-engine** — any file in `criticalPaths` gets a
  floor criticality score of 1.0 in the gap-prioritization formula
- **chaos-injector** — chaos scenarios that touch `criticalPaths`
  get the `critical: true` flag and cannot be skipped by `--mode
  gentle`

Declaring a path as critical is how you tell VibeFlow "this is
load-bearing — gate harder here". Think payment flows, auth
boundaries, tax calculation, customer balance math. Do NOT list
every file in your source tree — that defeats the gating rule.

## 7. What NOT to put in config

- **Feature flags** — VibeFlow does not read `featureFlags` from
  config. Flags live in your application code.
- **API credentials** for your application — those belong in your
  app's environment, not `vibeflow.config.json`.
- **Release version numbers** — the `release-decision-engine` reads
  these from `package.json` or git tags, not config.
- **Secrets of any kind** — sensitive values belong in `userConfig`
  or environment variables, never `vibeflow.config.json` (which is
  checked into git).
