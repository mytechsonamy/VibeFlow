# Getting Started with VibeFlow

VibeFlow is a Claude Code plugin that orchestrates the full software
development lifecycle — PRD analysis, test planning, code generation,
quality gating, and release decisions — against a set of truth-validated
invariants. This guide takes you from zero to a GO release decision on
your first project.

If you prefer to **read a complete walk-through** before installing
anything, the fastest path is `examples/demo-app/docs/DEMO-WALKTHROUGH.md`
inside this repo. It covers the same loop end-to-end against a real
sample project.

## 1. Prerequisites

- **Claude Code CLI** — `claude` command available ([install](https://claude.com/claude-code))
- **Node.js 18+** — `node --version` must show `v18` or higher
- **Git** — the sdlc-engine uses it for phase-aware commit guards
- **jq** and **sqlite3** — the hook scripts depend on both (preinstalled on macOS, `brew install jq sqlite` if missing on Linux it's already there)
- Optional: **PostgreSQL 13+** for team mode (13–16 exercised in the v1.2 test matrix; AWS RDS / GCP Cloud SQL / Azure Database also supported — see [TEAM-MODE.md](./TEAM-MODE.md#managed-cloud-postgres-aws-rds-gcp-cloud-sql-azure))
- Optional: **Figma personal access token** (only if you want `design-bridge` skills)
- Optional: **GitHub or GitLab personal access token** (only if you want `dev-ops` pipeline skills; GitLab SaaS or self-hosted — see [CONFIGURATION.md](./CONFIGURATION.md))

## 2. Install the plugin

### Option A — Local development install (recommended)

```bash
git clone https://github.com/mustiyildirim/vibeflow ~/Projects/VibeFlow
cd ~/Projects/VibeFlow
./build-all.sh              # builds all 5 MCP server dist/ directories

# launch Claude Code with the plugin loaded from source:
claude --plugin-dir ~/Projects/VibeFlow
```

### Option B — Marketplace install (when published)

```bash
claude plugin install vibeflow@vibeflow-marketplace
```

Either way, verify installation by running `/vibeflow:status` inside a
Claude Code session — it should respond with a "project not initialized"
hint.

## 3. Initialize your project

From your project's root directory:

```
/vibeflow:init
```

The command will prompt you for four fields:

| Field | Options | What it affects |
|-------|---------|-----------------|
| **project** | any string | Stable id used in every report and state record |
| **mode** | `solo` / `team` | Database, consensus reviewer count, hook strictness |
| **domain** | `financial` / `e-commerce` / `healthcare` / `general` | Quality thresholds + release decision weights |
| **platform** | `web` / `ios` / `android` / `all` | Test strategy defaults + generated test file shape |

The init creates `vibeflow.config.json` in your project root and a
hidden `.vibeflow/` directory for runtime state. See
[docs/CONFIGURATION.md](./CONFIGURATION.md) for the full reference of
every field and override.

## 4. First-run walkthrough

Once initialized, the "happy path" for a new feature is:

```
1. /vibeflow:prd-quality-analyzer docs/your-prd.md
   → .vibeflow/reports/prd-quality-report.md
2. /vibeflow:test-strategy-planner docs/your-prd.md
   → .vibeflow/reports/scenario-set.md + test-strategy.md
3. /vibeflow:advance DESIGN       (then ARCHITECTURE, PLANNING, DEVELOPMENT)
4. /vibeflow:component-test-writer src/your-module.ts
   → src/your-module.test.ts
5. # ... write your source code ...
6. /vibeflow:coverage-analyzer coverage-summary.json
7. /vibeflow:release-decision-engine
   → .vibeflow/reports/release-decision.md
```

Every step emits an artifact under `.vibeflow/reports/`. The
`release-decision-engine` reads those artifacts and applies your
domain's gate thresholds to produce one of three verdicts:

- **GO** — domain threshold cleared on every weighted gate
- **CONDITIONAL** — gates cleared but score below GO band
- **BLOCKED** — one or more hard-block conditions hit (zero-tolerance
  invariant violation, P0 uncovered, missing critical acceptance)

See [docs/PIPELINES.md](./PIPELINES.md) for the 7 canonical pipelines
and when to use each one.

## 5. Check status any time

```
/vibeflow:status
```

Returns the current phase, satisfied criteria, last consensus result,
and a summary of the .vibeflow/reports/ directory. This command is
safe to run often — it's read-only.

## 6. Solo vs team mode at a glance

| Feature | Solo | Team |
|---------|------|------|
| State store | SQLite (`.vibeflow/state.db`) | PostgreSQL (via `db_connection`) |
| Consensus reviewers | 1 (Claude) | 3 (Claude + ChatGPT + Gemini) |
| Consensus quorum | 1/1 | 3/3 (with 10-min timeout force-finalize) |
| Hook strictness | Essential only | All 7 hooks fire |
| Pipelines enabled | PIPELINE-1, PIPELINE-2, PIPELINE-5 | All 7 |
| Advance approval | Auto on criteria match | Human + consensus verdict required |

See [docs/TEAM-MODE.md](./TEAM-MODE.md) for the full team-mode setup
(PostgreSQL schema, multi-AI CLI configuration, collaborative advance
workflow).

## 7. The demo project

A complete sample project ships with VibeFlow at
`examples/demo-app/`. It is a small e-commerce product catalog with
real source code, 45 passing vitest tests, and four pre-baked
VibeFlow artifacts (prd-quality-report, scenario-set, test-strategy,
release-decision). Reading the demo takes about 15 minutes; running
it live takes about 45.

```bash
cd examples/demo-app
cat docs/DEMO-WALKTHROUGH.md         # 7-section guide
npm install && npm test              # see the live test suite (45 tests)
```

The walkthrough explains what each VibeFlow command does by pointing
at the artifact it produces. If you're not sure whether to read this
guide or run `/vibeflow:init` first, read the demo.

## 8. Where to go next

- **Configure** — [docs/CONFIGURATION.md](./CONFIGURATION.md) — full
  reference for `vibeflow.config.json`, `userConfig`, `test-strategy.md`
  overrides, and environment variables
- **Explore skills** — [docs/SKILLS-REFERENCE.md](./SKILLS-REFERENCE.md)
  — one section per skill with inputs, outputs, gate contract, and
  downstream consumers
- **Understand pipelines** — [docs/PIPELINES.md](./PIPELINES.md) —
  human-friendly walkthrough of the 7 canonical pipelines
- **Customize hooks** — [docs/HOOKS.md](./HOOKS.md) — what each of
  the 7 hook scripts does and how to customize / disable them
- **MCP internals** — [docs/MCP-SERVERS.md](./MCP-SERVERS.md) —
  architecture of the 5 MCP servers + tool listings
- **Debug problems** — [docs/TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
  — common failure modes with cause + fix
- **Scale to a team** — [docs/TEAM-MODE.md](./TEAM-MODE.md) —
  PostgreSQL setup, multi-AI consensus, collaboration workflow

## 9. Help

- **`/help`** — Claude Code's built-in help
- **Issues** — [github.com/mustiyildirim/vibeflow/issues](https://github.com/mustiyildirim/vibeflow/issues)
- **Report a bug in Claude Code itself** — [github.com/anthropics/claude-code/issues](https://github.com/anthropics/claude-code/issues)
