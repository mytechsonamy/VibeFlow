---
name: regression-test-runner
description: Runs the project's existing test suite at the scope appropriate for the trigger (smoke on PR, full on release, incremental on file change), diffs results against regression-baseline.json, classifies every test as passing / new-failure / still-failing / fixed / flaky, and enforces a P0 pass-rate gate. Gate contract — P0 pass rate must be exactly 100% before a run can update the baseline. PIPELINE-2 step 4 / PIPELINE-5 step 2.
allowed-tools: Read Write Bash(npm *) Bash(npx *) Bash(pnpm *) Bash(yarn *) Bash(git *) Grep Glob
context: fork
agent: Explore
---

# Regression Test Runner

An L2 Truth-Execution skill. Its job is to tell the delta since the
last green run: which tests regressed, which got fixed, which are
just flaky, which are still stuck red. The baseline is the memory
that makes that delta meaningful, and the gate contract is the rule
that keeps the baseline honest — **the baseline is never promoted
forward over a failing P0 test**.

Where `e2e-test-writer` generates tests and `uat-executor` runs
scenarios, this skill exercises the committed test suite. It doesn't
write code, it doesn't touch production, it doesn't try to interpret
a failure. That's what `test-result-analyzer` is for (Sprint 3
downstream).

## When You're Invoked

- **PIPELINE-2 step 4** — after a code change, before merge. Default
  scope is `smoke`. Fast feedback loop.
- **PIPELINE-5 step 2** — before a release tag. Default scope is
  `full`. Full audit.
- **On demand** as `/vibeflow:regression-test-runner [--scope <s>] [--since <sha>]`.
- **From `release-decision-engine`** when the decision engine needs
  a fresh baseline snapshot for the GO/CONDITIONAL call.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Trigger metadata | yes | One of `pr / push / release / manual` — determines default scope |
| `regression-baseline.json` | optional but preferred | Previous baseline. Absent → cold start (see §6). Present but stale → staleness block (see `references/baseline-policy.md`). |
| `--scope` | optional | `smoke / full / incremental`. Overrides the trigger's default. |
| `--since <sha>` | optional | For `incremental` scope: only run tests whose files changed since `<sha>`. Defaults to the trigger's base ref. |
| `test-strategy.md` | optional | Declares smoke includes/excludes + incremental affected-set rules. |
| `repo-fingerprint.json` | yes | Drives the test-runner dispatch — vitest vs jest vs playwright; unknown runner blocks. |
| Observability MCP | optional but preferred | `ob_track_flaky` is consulted to cross-check this run's flake candidates against the historical flake catalog. |

**Hard preconditions** — refuse to run rather than emit a baseline
nobody should trust:

1. The test runner declared in `repo-fingerprint.json` must be
   installed. A missing runner blocks with remediation "install <r>
   before re-running".
2. The working tree must be clean OR the run must be invoked with
   `--allow-dirty`. A dirty tree silently mixes uncommitted changes
   into the baseline, and the next run diffs against a history
   nobody can reconstruct.
3. `regression-baseline.json`, when present, must parse cleanly and
   match the current schema version. Malformed baseline → block
   with "delete the file and re-run to cold-start, or restore from
   git".

## Algorithm

### Step 1 — Determine scope
Default scope by trigger:

| Trigger | Default scope |
|---------|---------------|
| `pr` / `push` | `smoke` |
| `release` | `full` |
| `manual` | as specified, else `smoke` |

Explicit `--scope` always wins over the default. Scope rules from
`references/scope-selection.md`:

- **`smoke`** — the declared smoke set from `test-strategy.md`,
  plus every test file tagged `@smoke` in the suite, plus every
  P0 test regardless of tag.
- **`full`** — every test in the suite except those tagged
  `@slow:manual` (which require explicit opt-in).
- **`incremental`** — the affected set: every test whose file lives
  in the same directory subtree as a changed source file, plus
  every test that imports a changed source file (derived from
  `codebase-intel`'s dependency graph when available, otherwise
  falls back to directory-based proximity).

Record the resolved scope + the list of test files in the run
metadata — downstream consumers need to know what WASN'T run.

### Step 2 — Dispatch the runner
Select the runner from `repo-fingerprint.json`:

- `vitest` → `npx vitest run --reporter=json --outputFile=<run>.json <files>`
- `jest` → `npx jest --json --outputFile=<run>.json <files>`
- `playwright` → `npx playwright test --reporter=json <files>`

Every runner is invoked with a JSON reporter so `ob_collect_metrics`
can parse the output without re-running. Stdout + stderr are captured
into `per-run-stdout.log` / `per-run-stderr.log`. Exit code drives
only the "did the runner itself crash" signal; failure counts come
from the reporter.

**Timeout**: default 30 minutes for `full` scope, 5 minutes for
`smoke`, 2 minutes for `incremental`. Timeout is a hard fail, not a
"continue with what we have" — a timed-out run can't produce a
trustworthy baseline.

### Step 3 — Parse + normalize via observability
The skill does NOT re-implement reporter parsing. It calls
`observability` MCP's `ob_collect_metrics` with the generated
reporter JSON and consumes the resulting `NormalizedRun`. This keeps
the parser code in exactly one place.

If `observability` MCP is not loaded, the skill falls back to its
own minimal JSON parser for the detected framework, with a WARNING
in the run report noting the degraded mode. The minimal parser
handles vitest/jest/playwright via the same autoDetect strategy.

### Step 4 — Diff against the baseline
Load `regression-baseline.json`. For every `(testId, status)` pair
in the current run, classify against the baseline:

| Baseline status | Current status | Classification |
|-----------------|----------------|----------------|
| passed | passed | `still-passing` |
| passed | failed | **`new-failure`** (blocker signal) |
| passed | skipped | `skipped` (recorded but not graded) |
| failed | passed | `fixed` (celebrated in the report) |
| failed | failed | `still-failing` |
| absent | passed | `new-test-passing` |
| absent | failed | **`new-failure`** |
| absent | skipped | `new-test-skipped` |

Tests in the baseline that aren't in the current run are
`not-executed` — expected when scope is `smoke` or `incremental`,
suspicious when scope is `full`.

### Step 5 — Cross-check flakiness
For every test classified as `new-failure` or `still-failing`, call
`observability` MCP's `ob_track_flaky` with the rolling history
window. A test that the tracker classifies as `flaky` (score above
the configured threshold) gets re-classified from `new-failure` to
`flaky` in the regression report — but only when its priority is
below P0. A P0 test that is also flaky is recorded as BOTH
new-failure AND flaky: it blocks the gate regardless. Flakiness is
not a shield for P0 regressions.

### Step 6 — Compute the verdict + gate
```
p0Total     = tests where priority == "P0"
p0Failed    = tests where priority == "P0" && (status == "failed" || classification == "new-failure")
p0PassRate  = (p0Total - p0Failed) / p0Total    // 0..1

newFailures = classifications where class == "new-failure"  (P0 + non-P0 combined)
```

Verdict:

| Condition | Verdict |
|-----------|---------|
| `p0Total > 0 && p0PassRate == 1.0 && newFailures.length == 0` | PASS — baseline can be promoted |
| `p0Total > 0 && p0PassRate == 1.0 && newFailures.length > 0` | NEEDS_REVISION — non-P0 regressions, baseline NOT promoted |
| `p0Total > 0 && p0PassRate < 1.0` | BLOCKED — P0 regression, baseline NOT promoted |
| `p0Total == 0` | NEEDS_REVISION — "no P0 tests found" is a test-strategy problem, surface it |

**Gate contract: P0 pass rate must be exactly 100% — not 95%, not
99% — before a run can promote the baseline.** There is no rounding,
no "flaky allowance" for P0, no retry budget that papers over a
failing P0 test. The baseline is the memory of the project's
verified-green state, and the memory is allowed to be slow but not
allowed to lie.

### Step 7 — Baseline update policy
See `references/baseline-policy.md` for the full rules. Summary:

- **Only `PASS` verdicts promote the baseline.** NEEDS_REVISION and
  BLOCKED leave the baseline untouched.
- **Scope-constrained runs don't promote** — a `smoke` run only
  refreshes the smoke subset of the baseline; a `full` run is the
  only thing that refreshes every entry.
- **Append-only semantics** — a test that was failing in the baseline
  can only move to passing via a `PASS` run that includes it in
  scope. The inverse is never allowed: a `PASS` run with a
  now-missing test does NOT delete the baseline entry; it records
  `not-executed` and leaves the entry alone.
- **Baseline file includes a `lastPromotedAt` timestamp.** The
  staleness check uses this to block runs whose baseline is older
  than the configured staleness horizon.

### Step 8 — Write outputs

1. **`.vibeflow/reports/regression-report.md`** — the human-readable
   summary (see output contract below)
2. **`regression-baseline.json`** — updated **only** on verdict
   `PASS`, otherwise untouched
3. **`.vibeflow/artifacts/regression/<runId>/per-run.json`** — the
   full NormalizedRun the skill worked from
4. **`.vibeflow/artifacts/regression/<runId>/classified.json`** —
   the per-test classification from Step 4 (stable, consumable by
   `test-priority-engine` and `learning-loop-engine`)

## Output Contract

### `regression-report.md`
```markdown
# Regression Report — <runId>

## Header
- Run id: <runId>
- Trigger: pr | push | release | manual
- Scope: smoke | full | incremental
- Base ref: <sha>
- Runner: vitest | jest | playwright
- Started: <ISO>
- Duration: <ms>
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Summary
- Tests executed: N
- still-passing: a
- new-failure: b
- still-failing: c
- fixed: d
- flaky (reclassified): e
- skipped: f
- new-test-passing: g
- new-test-skipped: h
- P0 total: p
- P0 failed: q
- P0 pass rate: XX.X%

## Critical failures (gate-blocking)
### <testId>
- File: <file>
- Priority: P0
- Previously: passed
- Now: failed
- Error: <first 200 chars>
- Flaky cross-check: no | yes (score=0.XX)

## Non-critical regressions
<same shape, P1/P2/P3>

## Fixed tests (celebrate)
<list — informational only, no gate>

## Still failing
<list — these are in the baseline as red and remain red>

## Baseline state
- Previous baseline: <path>@<lastPromotedAt>
- Promoted this run: yes | no — <reason>
- Next staleness review: <ISO>
```

## Gate Contract
**P0 pass rate must be exactly 100% before a run can update the
baseline.** Three ways to violate it and their responses:

1. Any P0 test failed in the current run → BLOCKED; baseline
   untouched; report names the test.
2. Any test classified `new-failure` (regardless of priority) →
   NEEDS_REVISION; baseline untouched; report names the tests.
3. P0 count is 0 → NEEDS_REVISION; "no P0 tests found" is a
   test-strategy gap, not a silent pass.

No override flag. If a P0 test needs to be quarantined, the human
fix is in `test-strategy.md` (remove the P0 tag or mark the test
`@quarantined`) — not in this skill.

## Non-Goals
- Does NOT write tests (`component-test-writer` / `e2e-test-writer`).
- Does NOT interpret failures (`test-result-analyzer`).
- Does NOT auto-retry failed tests. Retries are set at the runner
  config level and are out of scope for this skill.
- Does NOT modify source code to "fix" failures.
- Does NOT promote a baseline on a dirty working tree unless
  `--allow-dirty` is explicitly set (and then it writes a
  `dirtyPromotion: true` flag into the baseline metadata so
  downstream can tell).
- Does NOT run against `uat-executor`'s live environments — that's
  scenario-driven, this is suite-driven.

## Downstream Dependencies
- `test-priority-engine` — reads `classified.json` to rank
  "which tests are most worth running next"
- `learning-loop-engine` — consumes baseline diffs across time to
  learn which code areas regress together
- `release-decision-engine` — reads `regression-report.md`'s verdict
  + the P0 pass rate as a hard blocker signal
- `observability-analyzer` — ingests timing data from
  `per-run.json` to feed `ob_perf_trend`
