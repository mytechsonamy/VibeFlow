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
- **jq** — the hook scripts depend on it (preinstalled on macOS; `brew install jq` / `apt install jq` otherwise)
- Optional: **Figma personal access token** (only if you want `design-bridge` skills)
- Optional: **GitHub or GitLab personal access token** (only if you want `dev-ops` pipeline skills; GitLab SaaS or self-hosted — see [CONFIGURATION.md](./CONFIGURATION.md))

## 2. Install the plugin

### Option A — Marketplace install (recommended for end users)

Register the marketplace directly from the GitHub repo, then install.
Claude does a shallow `git clone` of the repo ref — `node_modules` and
other gitignored content never leave the author's laptop.

```bash
claude plugin marketplace add github:mytechsonamy/VibeFlow
claude plugin install vibeflow@vibeflow
```

The install pulls a ~3 MB tree (5 bundled MCP servers plus the
skills/hooks/config surface) and completes in seconds.

### Option B — Local development install

If you want to iterate on the plugin itself (edit skills, MCP servers,
hooks) load it directly from the clone:

```bash
git clone https://github.com/mytechsonamy/VibeFlow ~/Projects/VibeFlow
cd ~/Projects/VibeFlow
./build-all.sh              # builds dist/ + dist/bundle.js for each MCP

# launch Claude Code with the plugin loaded from source:
claude --plugin-dir ~/Projects/VibeFlow
```

Use `--plugin-dir` rather than `claude plugin marketplace add <path>`
for the local-path case — the directory-type marketplace does a
recursive copy that includes your populated `node_modules` (hundreds of
megabytes across the five MCP servers) and can take minutes to complete.

Either way, verify installation by running `/vibeflow:status` inside a
Claude Code session — it should respond with a "project not initialized"
hint.

## 3. Initialize your project

From your project's root directory:

```
/vibeflow:onboard
```

The command will prompt you for three fields:

| Field | Options | What it affects |
|-------|---------|-----------------|
| **project** | any string | Stable id used in every report and state record |
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

## 6. State layout

VibeFlow writes everything it knows about your project under one
directory:

```
.vibeflow/state/<projectId>/
├── project.json              # authoritative current state
├── project.json.lock         # cross-process write lock
├── INDEX.md                  # human-readable chronological index
├── events/                   # append-only JSON+MD event log
└── archive/NN-<PHASE>/       # moves here when a phase completes
```

Git versions the whole thing for free — if you commit `.vibeflow/`
alongside your source, every state transition shows up as a reviewable
diff and you can `git revert` a bad phase advance. `cat` is enough to
inspect the current state at any time.

See [CONFIGURATION.md](./CONFIGURATION.md) for the `VIBEFLOW_STATE_DIR`
override and the recovery tools (`bin/replay-events.sh`).

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
guide or run `/vibeflow:onboard` first, read the demo.

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

## 9. Help

- **`/help`** — Claude Code's built-in help
- **Issues** — [github.com/mustiyildirim/vibeflow/issues](https://github.com/mustiyildirim/vibeflow/issues)
- **Report a bug in Claude Code itself** — [github.com/anthropics/claude-code/issues](https://github.com/anthropics/claude-code/issues)
