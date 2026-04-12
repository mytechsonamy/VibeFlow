---
name: test-priority-engine
description: Ranks the test suite by risk so the highest-leverage tests run first. Consumes changed files + regression-baseline.json + ob_track_flaky history, applies a deterministic risk model, and emits priority-plan.md. Gate contract — every affected P0 test appears in the plan, regardless of mode budget. PIPELINE-2 step 1 / PIPELINE-5 step 1.
allowed-tools: Read Write Bash(git *) Grep Glob
context: fork
agent: Explore
---

# Test Priority Engine

An L2 Truth-Execution skill. It doesn't run tests — it decides what
order `regression-test-runner` (or a human operator) should run them
in, and it caps the plan to a time budget that matches the CI stage
the user is in. Fast feedback is a product; exhausting the test suite
every commit isn't.

The risk model is deterministic and documented in
`references/risk-model.md`. The mode budgets are in
`references/mode-budgets.md`. Both files are load-bearing — a weak
priority is how "the tests I should have run" becomes "the bug I
shipped".

## When You're Invoked

- **PIPELINE-2 step 1** — before `regression-test-runner` on an
  incremental PR run. The plan produced here becomes the input
  `--scope=incremental` for the runner.
- **PIPELINE-5 step 1** — before the pre-release regression run. The
  plan is used as a scheduling hint so the highest-risk tests run
  earliest, and a failure trips the gate before the long tail.
- **On demand** as `/vibeflow:test-priority-engine [--mode <m>] [--since <sha>]`.
- **From `regression-test-runner`** when it needs the ordering for
  its own Step 1 scope resolution.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Changed files list | yes | From `git diff --name-only <since>..HEAD` or an explicit file list. Empty list → "no risk signal"; the skill emits a full-suite plan sorted by priority-only fallback and WARNs. |
| `regression-baseline.json` | optional but preferred | Used for baseline fail counts + per-test duration + tags. Absent → cold-start fallback (see mode-budgets.md §4). |
| `scenario-set.md` | optional | Links tests to scenarios; scenarios carry `priority` which can override file-level priority. |
| `.vibeflow/artifacts/observability/flakiness.json` | optional | Latest `ob_track_flaky` output. When present, flake score feeds the risk model. |
| `codebase-intel` MCP | optional | `ci_dependency_graph` gives the transitive import graph so affected-set calculation isn't limited to directory proximity. |
| Mode | optional | One of `quick / smart / full`. Default derived from trigger (see §4). |
| Budgets override | optional | `--time-budget <seconds>` / `--count-budget <n>` — if present, always tightens the defaults, never loosens. |

**Hard preconditions** — refuse rather than emit a plan the user
should not trust:

1. At least ONE priority signal must exist. If ALL of these are
   absent — no changed files, no baseline, no flakiness history,
   no scenario-set — the skill refuses with remediation "not enough
   signal to prioritize; run a full regression first to establish
   a baseline".
2. `--mode` must be one of the three canonical values. Typos
   (`quik`) block — silent defaulting is how modes silently shift.
3. If `--time-budget` is set, it must be positive and ≥ 10 seconds.
   A 5-second budget is a footgun — the skill would emit an empty
   plan.

## Algorithm

### Step 1 — Resolve the mode + budgets
Default mode by trigger:

| Trigger | Default mode |
|---------|--------------|
| `pr` / `push` | `quick` |
| `release` | `smart` |
| `manual` | `smart` |
| PIPELINE-5 pre-release | `full` (regardless of trigger) |

See `references/mode-budgets.md` for the concrete time/count
budgets per mode. User overrides (`--time-budget` / `--count-budget`)
only TIGHTEN, never loosen — a mode is a floor, not a ceiling.

### Step 2 — Derive the affected set
For every changed source file:

1. Call `codebase-intel` MCP's `ci_dependency_graph` to get
   transitive dependents.
2. For each dependent, find test files that import it (either
   directly or via the project's module resolver).
3. Add those test files to the affected set.
4. If `codebase-intel` is unavailable, fall back to directory
   proximity: every `*.test.*` / `*.spec.*` file under the same
   directory subtree as a changed file. The fallback is less
   precise but never misses a test; record "degraded affected-set
   derivation" in the run report so consumers know.

A test can be in the affected set for multiple changed files —
that's a signal; it becomes part of the risk score (see
`risk-model.md`).

### Step 3 — Score every candidate
The candidate set is the union of:

- The affected set from Step 2
- Every P0 test in the baseline (P0 tests are always candidates)
- Every test in `regression-baseline.json.flakyKnown`

For each candidate, compute a risk score using the formula in
`references/risk-model.md`. The score is a pure function of the
inputs; two runs with identical inputs produce identical scores.

### Step 4 — Enforce the P0 mandatory set
**Every affected P0 test appears in the plan regardless of mode or
budget.** This is the gate contract. The budget squeezes non-P0
tests first, then P1, then P2, then P3 — but a P0 test that maps
to a changed file is pinned in the plan as a non-negotiable
inclusion.

If the P0 mandatory set alone exceeds the mode budget, the skill
emits the full P0 set and records the budget overflow in the report
as `budgetExceeded: true, reason: "P0 mandatory set"`. The run
continues — exceeding the budget for P0 coverage is the right
trade-off and the operator sees exactly why.

### Step 5 — Budget-fit the non-P0 tail
Sort the non-P0 candidates by risk score descending. Pack them into
the remaining budget (time budget preferred; falls back to count
budget when per-test duration is unknown — see mode-budgets.md §3
for the cold-start path).

Packing is first-fit by risk score. Tests that don't fit are NOT
silently dropped — they go into the plan's "spill list" with their
score and the reason they didn't fit. `regression-test-runner` +
humans can decide to run them in a follow-up pass.

### Step 6 — Write the plan
Emit `.vibeflow/reports/priority-plan.md`. Every test entry includes:

- Scheduled position (1..N)
- Test id + file
- Risk score + contributing factors (so the human can tell WHY)
- Priority tier
- Expected duration (from baseline)
- Cumulative budget used (running total)

The report is deterministic — same inputs, byte-identical output.
Downstream tools can cache the plan and re-use it when inputs
haven't changed.

## Output Contract

### `priority-plan.md`
```markdown
# Priority Plan — <runId>

## Header
- Mode: quick | smart | full
- Time budget: 300s
- Count budget: 100
- Since: <base sha>
- Candidate pool: N tests (affected=a, p0=b, flakyKnown=c)
- Planned: P
- Spilled: S
- Budget exceeded: no | yes (reason: <reason>)

## Plan
| # | Test id | File | Prio | Risk | Duration | Cumulative | Reason |
|---|---------|------|------|------|----------|------------|--------|
| 1 | auth.test.ts::login >... | tests/unit/auth.test.ts | P0 | 0.92 | 17ms | 17ms | affected + baseline-fail×2 + P0 weight |
| 2 | ... |

## Spill (over budget)
| Test id | Prio | Risk | Reason it didn't fit |
|---------|------|------|----------------------|
| ... | P2 | 0.34 | time budget exhausted at 290/300s |

## Degraded signals (if any)
- codebase-intel unavailable — used directory-proximity fallback
- flakiness.json missing — risk score omits flake component
```

### Machine-readable counterpart
`.vibeflow/artifacts/priority/plan-<runId>.json` — same data in a
stable JSON shape consumed by `regression-test-runner` and
`learning-loop-engine`. Fields match the table columns 1:1.

## Gate Contract
**Every affected P0 test appears in the plan, regardless of mode or
budget.** No other condition can push a P0 out. Three ways to
misinterpret this and their responses:

1. P0 mandatory set exceeds the budget → plan emits the full P0
   set with `budgetExceeded: true`. The operator sees the reason
   and can decide to raise the budget or split the run.
2. A P0 test has no baseline entry (cold start, new test file) →
   it still lands in the plan, with risk score computed from
   priority weight alone and `degradedSignals: ["no baseline"]`
   noted on its row.
3. A P0 test is tagged `@quarantined` → it is NOT in the plan.
   Quarantine is the human's explicit decision to ignore a test;
   the priority engine respects it. The plan's header notes the
   quarantined count so humans can audit.

## Non-Goals
- Does NOT run tests.
- Does NOT modify `regression-baseline.json`.
- Does NOT invent priority tiers; the priority comes from
  `scenario-set.md` / `baseline.tags` / the test file's own tags.
- Does NOT try to predict which tests will fail. Risk is a
  historical + structural signal, not a failure oracle.
- Does NOT retry or re-order on failure. Order is decided up
  front and written once.

## Downstream Dependencies
- `regression-test-runner` — consumes the plan as an ordering hint
  when it dispatches tests. `incremental` scope can use the plan's
  top-K directly.
- `learning-loop-engine` — ingests plans + outcomes over time to
  learn which risk factors predict real failures.
- `release-decision-engine` — reads the plan's `budgetExceeded`
  flag as a gate signal (a release run should never be budget-
  exceeded; the pre-release pipeline has no time ceiling).
- `observability-analyzer` — correlates plan position with actual
  failure outcomes to feed a feedback loop into the risk model.
