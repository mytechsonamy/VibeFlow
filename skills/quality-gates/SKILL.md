---
name: quality-gates
description: Run the project's lint + typecheck + unit-test commands (resolved from vibeflow.config.json.tech.*) and auto-satisfy the DEVELOPMENT phase's `quality.gates.passed` exit criterion when all three exit 0. Pairs with consensus-orchestrator, which satisfies `code.reviewed` on APPROVED verdicts. Together they unblock DEVELOPMENT → TESTING advance without manual MCP calls.
allowed-tools: Read Write Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(mypy *) Bash(tsc *) Bash(eslint *) Bash(prettier *) Bash(pytest *) Bash(dotnet *) Bash(ruff *) Bash(black *) Bash(cargo *) Bash(go *)
---

# Quality Gates (DEVELOPMENT)

Sprint 18-F. Runs the project's quality checks and records the
outcome. Satisfies `quality.gates.passed` — one of two DEVELOPMENT
phase exit criteria (the other, `code.reviewed`, is satisfied by
consensus-orchestrator on APPROVED commit-time review).

## Phase Contract

Runs in **DEVELOPMENT** only. Before any step, read
`vibeflow.config.json.currentPhase`. If it is not DEVELOPMENT,
emit:

```
quality-gates only runs in DEVELOPMENT. Current phase: <x>. Stopping.
```

and exit without running commands.

## Input

Read `vibeflow.config.json`:

```
TECH = config.tech // { language, framework, testRunner, ... }
```

Supported config keys (all optional — missing keys become
"skipped" steps, not failures):

| Key                       | Default inferred from | Example                |
|---------------------------|-----------------------|-------------------------|
| `tech.lintCommand`        | language              | `npm run lint` / `ruff check` / `eslint .` |
| `tech.typecheckCommand`   | language              | `npm run typecheck` / `mypy .` / `tsc --noEmit` |
| `tech.testCommand`        | `tech.testRunner`     | `npm test` / `pytest` / `dotnet test` |

If the operator hasn't set these, the skill **infers sensible
defaults from `tech.language`**:

| `tech.language` | lint                       | typecheck       | test             |
|-----------------|----------------------------|-----------------|------------------|
| `typescript`    | `npm run lint` (if script) / `eslint .` | `npx tsc --noEmit` | `npm test` |
| `javascript`    | `eslint .`                 | _(skip)_        | `npm test`       |
| `python`        | `ruff check .` / `flake8`  | `mypy .`        | `pytest`         |
| `csharp`/`dotnet`| `dotnet format --verify-no-changes` | _(skip)_ | `dotnet test` |
| `go`            | `go vet ./...`             | _(skip)_        | `go test ./...`  |
| `rust`          | `cargo clippy -- -D warnings` | _(skip)_     | `cargo test`     |

If **all three** inferred commands come up empty (unknown
`tech.language` + no explicit commands), emit:

```
quality-gates: no runnable commands (tech.language=<x> unrecognised,
no explicit tech.lintCommand / tech.typecheckCommand /
tech.testCommand). Configure vibeflow.config.json.tech.*
and re-run.
```

and exit without satisfying the criterion.

## Process

### Step 1: Resolve commands

Read each command from config (or infer). Record which commands
will run vs. skip. Abort if NO commands are resolved (see above).

### Step 2: Run each command in order

```
lint       → exit code N1
typecheck  → exit code N2
test       → exit code N3
```

Capture stdout/stderr for each. If any command doesn't exist
on PATH (e.g. `eslint` not installed), treat it as **skipped with
warning** (not a failure) — but log the missing tool prominently
so the operator sees it. `quality.gates.passed` is only
satisfied if every ACTUALLY RUN command exited 0.

The three commands run sequentially. A failed earlier command
does NOT short-circuit — run all three and report the union of
findings so the operator sees everything that needs fixing.

### Step 3: Write report

`.vibeflow/reports/quality-gates-<YYYYMMDD-HHMMSS>.md`:

```markdown
# Quality Gates — <project> — <timestamp>

Verdict: **PASS | FAIL | PARTIAL**

## Lint (<command>)
Exit code: <N1>
<captured output, truncated to ~80 lines>

## Typecheck (<command>)
Exit code: <N2>
<captured output>

## Tests (<command>)
Exit code: <N3>
<captured output>

## Summary
- Ran: <N> commands
- Skipped: <M> commands (see warnings above)
- Failed: <K> commands
```

Verdict rules:
- **PASS**: every command that ran exited 0, at least one
  command ran (i.e. at least one of lint/typecheck/test was
  actually invoked)
- **PARTIAL**: every command that ran exited 0 BUT the "ran"
  count is less than the "intended" count because some tools
  were missing on PATH. `quality.gates.passed` is NOT satisfied
  on PARTIAL — the operator should install the missing tool.
- **FAIL**: at least one command that ran exited non-zero

### Step 4: Auto-satisfy `quality.gates.passed` (MANDATORY on PASS)

**Only when verdict == PASS**, call:

```
mcp__sdlc-engine__sdlc_satisfy_criterion {
  "projectId": "<project id from config>",
  "criterion": "quality.gates.passed"
}
```

Emit:

```
Recorded: quality.gates.passed (lint ✓ typecheck ✓ tests ✓).
```

On PARTIAL or FAIL, emit a visible advisory naming the failing
command + a suggested fix, and do NOT call the MCP tool.

Fallback on MCP unavailability:

```
sdlc-engine MCP unavailable — satisfy manually:
mcp__sdlc-engine__sdlc_satisfy_criterion {projectId:…, criterion:'quality.gates.passed'}
```

## Output

- `.vibeflow/reports/quality-gates-<timestamp>.md`
- State update (criterion satisfied) via MCP — visible in
  `/vibeflow:flow-status`

## Guardrails

- **No auto-fix.** The skill reports; it doesn't format, lint-fix,
  or modify source. Operator runs `npm run lint -- --fix` etc.
  themselves.
- **No marker write.** Unlike the analysis skills, quality-gates
  doesn't require a consensus review — the signal is purely
  tool-based. No `consensus-needed.json` marker; no orchestrator
  chain.
- **Idempotent.** Re-running on a clean tree is a no-op at the
  state level (`sdlc_satisfy_criterion` returns
  `alreadyPresent: true`). The report still regenerates with a
  fresh timestamp so audit history is preserved.

## Non-goals

- Does NOT run integration tests, e2e tests, or performance
  tests. Those have their own skills (e2e-test-writer,
  regression-test-runner, chaos-injector) in TESTING phase.
- Does NOT gate on code coverage — that's `coverage-analyzer`'s
  job (TESTING phase).
- Does NOT satisfy `code.reviewed` — that's the orchestrator's
  job on APPROVED commit-time review (Sprint 18-E).

## See also

- `docs/AUTO-SATISFY.md` — full per-criterion matrix
- `/vibeflow:advance` — move DEVELOPMENT → TESTING once both
  DEVELOPMENT criteria are satisfied
- Sprint 18 release notes for the pattern that replaces manual
  `sdlc_satisfy_criterion` calls
