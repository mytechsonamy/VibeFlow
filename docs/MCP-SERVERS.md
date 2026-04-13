# MCP Servers

VibeFlow ships **5 MCP servers** that the plugin loads via `.mcp.json`.
Each is a separate Node process spoken to via stdio JSON-RPC. Skills
call into these servers when they need state-aware operations — phase
tracking, code analysis, design-token lookup, CI orchestration,
test-execution metrics.

| Server | State? | External calls? | Tools |
|--------|--------|-----------------|-------|
| `sdlc-engine` | yes (SQLite or Postgres) | no | 5 (phase + consensus + state) |
| `codebase-intel` | no (per-call analysis) | no | 4 (structure / deps / hotspots / debt) |
| `design-bridge` | no (lazy Figma client) | yes (Figma REST) | 4 (fetch / extract / generate / compare) |
| `dev-ops` | no (lazy GitHub client) | yes (GitHub REST) | 5 (pipeline trigger / status / artifacts / deploy / rollback) |
| `observability` | no (per-call analysis) | no | 4 (metrics / flaky / trends / dashboard) |

The wiring lives in `.mcp.json` at the repo root. You should not edit
it — the plugin owns it. Token-bearing servers (`design-bridge`,
`dev-ops`) flow secrets via `${userConfig.<key>}` template strings so
no credentials hit the plugin source.

---

## sdlc-engine

**Path**: `mcp-servers/sdlc-engine/`
**Dist**: `mcp-servers/sdlc-engine/dist/index.js`
**Tests**: 104 vitest cases, 93.01% statement / 88.62% branch coverage

The authoritative state store for VibeFlow projects. Every phase
advance, every consensus result, and every satisfied-criterion update
flows through this server. Hooks read the current state via the
shared `_lib.sh` helpers; skills read it via the MCP tool calls.

### Storage

| Mode | Backend | Connection |
|------|---------|------------|
| solo | SQLite | `<cwd>/.vibeflow/state.db` (or `VIBEFLOW_SQLITE_PATH`) |
| team | PostgreSQL | `userConfig.db_connection` DSN |

The two backends share the same logical schema (`project_state`
table) so a project can migrate between modes without losing
state. The Postgres path uses connection pooling with idle-client
recovery (test count: 14 covering the resilience paths).

### Schema

```sql
CREATE TABLE project_state (
  project_id          TEXT    PRIMARY KEY,
  current_phase       TEXT    NOT NULL,           -- REQUIREMENTS..DEPLOYMENT
  satisfied_criteria  TEXT    NOT NULL,           -- JSON array of criterion ids
  last_consensus      TEXT,                       -- JSON object {phase, status, agreement, criticalIssues, recordedAt}
  updated_at          TEXT    NOT NULL,           -- ISO timestamp
  revision            INTEGER NOT NULL            -- monotonic, optimistic-lock cursor
);
```

The `revision` column is a CAS cursor — every write increments it,
and concurrent writers re-read on conflict. Same shape in both
backends.

### Tools

| Tool | Purpose |
|------|---------|
| `sdlc_list_phases` | Returns the canonical phase order (REQUIREMENTS → DEPLOYMENT) |
| `sdlc_get_state` | Reads `project_state` for a project id |
| `sdlc_advance_phase` | Moves to a new phase if entry criteria are met |
| `sdlc_satisfy_criterion` | Marks a criterion as satisfied |
| `sdlc_record_consensus` | Records a consensus verdict (phase + status + agreement + critical count) |

### Phase order

```
REQUIREMENTS → DESIGN → ARCHITECTURE → PLANNING → DEVELOPMENT → TESTING → DEPLOYMENT
       0         1         2              3          4              5         6
```

Phase advances are gated on entry criteria. The default criteria
per phase live in `mcp-servers/sdlc-engine/src/phases.ts`; team mode
also requires a non-REJECTED `last_consensus` for the source phase.

---

## codebase-intel

**Path**: `mcp-servers/codebase-intel/`
**Dist**: `mcp-servers/codebase-intel/dist/index.js`
**Tests**: 46 vitest cases, 93.00% statement / 80.75% branch coverage

Per-call code analysis for any project. Reads files from disk;
holds no state between calls. Used by skills that need to reason
about source structure, dependencies, hotspots, or technical debt.

### Tools

| Tool | Purpose |
|------|---------|
| `ci_analyze_structure` | Detects language + runtime + frameworks + entry points |
| `ci_dependency_graph` | Builds the import graph for a directory |
| `ci_find_hotspots` | Returns files ranked by recent commit churn (uses git log) |
| `ci_tech_debt_scan` | Reports TODO/FIXME/HACK markers + complexity hotspots |

The hotspot tool falls back to `git log --since=30.days.ago --oneline
-- <file> | wc -l` when the git history is too small for the
internal heuristic. The other three tools are file-system-only.

---

## design-bridge

**Path**: `mcp-servers/design-bridge/`
**Dist**: `mcp-servers/design-bridge/dist/index.js`
**Tests**: 54 vitest cases, 90.08% statement / 86.06% branch coverage
**Token**: `userConfig.figma_token` (sensitive)

Bridges Figma to source code. Fetches design files, extracts tokens
(colors, spacing, typography), generates style files (Tailwind config,
CSS variables), and compares rendered screenshots against design
frames pixel-by-pixel.

### Token requirement

Three of the four tools call the Figma REST API. Without a token
they fail with a clear error message. The fourth tool
(`db_compare_impl`) is filesystem-only and works without a token —
it does PNG-vs-PNG comparison, used by `visual-ai-analyzer`'s
structural pre-check.

The Figma client is **lazily constructed** at first call so
`tools/list` works without ever hitting the token branch (verified
by integration harness `run.sh [4c]`).

### Tools

| Tool | Token? | Purpose |
|------|--------|---------|
| `db_fetch_design` | yes | Fetches a Figma file by URL or file id |
| `db_extract_tokens` | yes | Pulls colors / spacing / typography tokens |
| `db_generate_styles` | yes | Generates Tailwind config or CSS vars from extracted tokens |
| `db_compare_impl` | **no** | Compares two PNGs (used by visual-ai-analyzer's preflight) |

`db_compare_impl` returns one of three verdicts: `identical` /
`size-mismatch` / `pixel-diff` (with a percentage). Size mismatch
short-circuits the pipeline before the AI vision call.

---

## dev-ops

**Path**: `mcp-servers/dev-ops/`
**Dist**: `mcp-servers/dev-ops/dist/index.js`
**Tests**: 37 vitest cases, 91.17% statement / 91.07% branch coverage
**Token**: `userConfig.github_token` (sensitive)

Bridges VibeFlow to GitHub Actions for CI/CD orchestration. Triggers
workflows, polls run status, fetches artifacts, deploys to staging,
rolls back on failure.

### Token requirement

The token needs `actions:write` (to trigger workflows) and
`contents:read` (to read repo metadata). Without a token, all
five tools fail with an explicit error. Same lazy-construction
pattern as `design-bridge` — `tools/list` works token-free.

### Tools

| Tool | Purpose |
|------|---------|
| `do_trigger_pipeline` | Dispatches a GitHub Actions workflow with payload |
| `do_pipeline_status` | Polls a run id for status (queued / in_progress / completed) |
| `do_fetch_artifacts` | Downloads build artifacts from a completed run |
| `do_deploy_staging` | Triggers the staging deployment workflow |
| `do_rollback` | Reverts to the previous green deployment via the rollback workflow |

The five tools are stateless wrappers around `octokit.actions.*`.
Real CI orchestration logic lives in your GitHub Actions workflow
files; the MCP just provides the trigger surface.

---

## observability

**Path**: `mcp-servers/observability/`
**Dist**: `mcp-servers/observability/dist/index.js`
**Tests**: 76 vitest cases, 97.57% statement / 88.62% branch coverage

Per-call analysis of test runner output and execution metrics. No
network calls; no state between invocations. Reads vitest / jest /
playwright reporter payloads (inline or from a path), normalizes
them into a `NormalizedRun` shape, and computes metrics, flakiness
scores, performance trends, and a compact health dashboard.

### Tools

| Tool | Purpose |
|------|---------|
| `ob_collect_metrics` | Parses a reporter payload, returns counts + per-file breakdown |
| `ob_track_flaky` | Identifies flaky tests across N runs (history dir or inline runs) |
| `ob_perf_trend` | Detects slowdown regressions across a window of runs |
| `ob_health_dashboard` | Returns a green/yellow/red grade + reasoning |

### Reporter auto-detect

`ob_collect_metrics` accepts payloads from any of the supported
reporters and auto-detects the framework:

- **vitest** — `testResults` + `numTotalTests` shape, identified
  via `location` field on assertions
- **jest** — same shape as vitest minus the `location` field
- **playwright** — `suites` + `config.projects` shape

The auto-detect fall-through is `vitest` → `jest` → `playwright`,
matching the actual format precision (vitest is most specific).
Adding a new framework means: write a `parseX` function, teach
`autoDetect` to recognize its shape, add to the union type, extend
the integration sentinel.

### Flakiness scoring

A test that passes once and fails once across 4 runs is more flaky
than a test that fails twice in a row. The scoring formula:

```
base       = min(passes, failures) / total
interleave = 1 for pass↔fail interleave, 0 for pure blocks
score      = base * (0.5 + 0.5 * interleave)
```

The interleave bonus reflects that intermittent failures are harder
to diagnose than a consistent failure block.

---

## Running an MCP server outside the plugin

Every MCP server can be run standalone for debugging:

```bash
cd mcp-servers/sdlc-engine
node dist/index.js < /dev/null     # runs in stdio mode; ctrl-c to exit
```

For a full JSON-RPC handshake, use the `tests/integration/run.sh`
smoke fixtures as templates — sections `[4]`, `[4b]`, `[4c]`,
`[4d]`, `[4e]` show the exact `initialize` → `tools/list` →
`tools/call` sequence each server expects.

## Building / rebuilding

```bash
cd mcp-servers/<server> && npm install && npm run build
```

Or build all five at once:

```bash
./build-all.sh
```

The `dist/index.js` files are checked into the repo so an end-user
install doesn't require a build step. CI ensures the dist files
parse on every PR (`run.sh [3]` section's `node --check` block).
