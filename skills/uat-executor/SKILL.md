---
name: uat-executor
description: Executes UAT scenarios against a live staging environment, walks automated steps via a runner (playwright/detox) and human-in-the-loop steps via prompts, collects evidence (screenshots + timings + console) on every step, and emits uat-raw-report.md. Gate contract — every failed step must carry evidence, every P0 scenario must be executed. PIPELINE-3 step 3.
allowed-tools: Read Write Bash(playwright *) Bash(detox *) Bash(curl *) Grep Glob
context: fork
agent: Explore
---

# UAT Executor

An L2 Truth-Execution skill. Where `e2e-test-writer` **produces** test
files, this skill **runs** scenarios against a real environment and
records what happened. The output is `uat-raw-report.md` — the raw
material that `test-result-analyzer`, `observability-analyzer`, and
`release-decision-engine` all consume to make the GO/CONDITIONAL/BLOCKED
call. Lying in that raw material poisons every downstream decision, so
the skill's whole job is "run honestly and capture evidence".

## When You're Invoked

- During PIPELINE-3 step 3, after `e2e-test-writer` has landed
  automated specs and the environment is ready for UAT.
- On demand as `/vibeflow:uat-executor <env> <scenario-glob>`.
- From `release-decision-engine` before a CONDITIONAL release, when
  a fresh UAT run is required before sign-off.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| `scenario-set.md` | yes | Output of `test-strategy-planner`. Only scenarios tagged `uat` or `e2e+uat` are executed; others are owned by different skills. |
| Target environment | yes | `--env <name>` — must resolve to a URL in `vibeflow.config.json.environments.<name>`. `production` is rejected at the precondition stage (UAT against production is not UAT). |
| `test-strategy.md` | optional | When present, informs per-scenario retry policy and halt policy overrides. |
| Runner availability | derived | `playwright` / `detox` via `repo-fingerprint.json`. Automated steps require the matching runner; without one, automated steps block. |
| Evidence sink | yes | Path under `.vibeflow/artifacts/uat/<runId>/` where screenshots + console + timings land. Writable directory required. |
| Human-in-the-loop channel | derived | When the scenario has human steps, the skill emits interactive prompts and blocks on operator response. Non-interactive invocations (CI) auto-skip human steps and record them as `skipped-noninteractive`, never as `passed`. |

**Hard preconditions** — refuse to run rather than emit a report that
poisons downstream decisions:

1. Target environment MUST NOT be `production` or any environment
   tagged `prod: true` in the config. UAT runs against staging, full
   stop — even if the caller claims otherwise.
2. The evidence sink directory must exist (or be creatable) and must
   be writable. A run that can't collect evidence is a run that can't
   be audited.
3. Every P0 scenario in scope must have at least one expected
   outcome. P0 scenarios with no assertion block with "scenario lacks
   a measurable outcome" — we do not execute P0 scenarios on faith.

## Algorithm

### Step 1 — Resolve environment + runner
Read `vibeflow.config.json.environments[env]` to get the base URL (or
bundle id for mobile). Refuse if the resolved environment has
`prod: true`. Record the resolved URL in the run report — downstream
consumers need it to correlate failures with deploy events.

Probe the runner (`playwright --version` / `detox -v`). A missing
runner is a hard blocker with remediation: "install the runner
declared in repo-fingerprint.json before re-running".

### Step 2 — Create the run directory
Create `.vibeflow/artifacts/uat/<runId>/` where `runId` is a sortable
timestamp (`YYYYMMDD-HHMMSS-<short-hash>`). Write
`run-metadata.json` first so even a crashed run leaves a breadcrumb:

```json
{
  "runId": "20260413-120000-abc1234",
  "startedAt": "2026-04-13T12:00:00Z",
  "env": "staging",
  "targetUrl": "https://staging.example.com",
  "scenarioSet": "scenario-set.md@<gitSha>",
  "executor": "uat-executor@0.1.0",
  "operator": "<user or ci>"
}
```

### Step 3 — Select scenarios
Walk `scenario-set.md` and keep scenarios that:

- have `phase: uat` OR `phase: e2e+uat`
- match the invocation's scenario glob (default: `*`)
- resolve to the invocation's platform (web/ios/android/all)
- are not tagged `status: deferred`

Sort the surviving set by priority descending (P0 first) so the most
important coverage lands before a flaky step trips a halt. Group by
`dependsOn` chains so prerequisite scenarios run before their dependents.

### Step 4 — Walk each scenario
For each scenario, walk its `steps` list in order. Every step has
exactly one of three types — the skill refuses to execute a step
with an ambiguous type:

1. **`automated`** — handed to the runner. `playwright test` / `detox test`
   with the step's target selector and expected outcome. Exit code
   drives pass/fail; stdout/stderr is captured; a screenshot is
   written to the evidence sink on failure.
2. **`human`** — the step asks the operator to observe something
   ("verify the receipt email arrives within 2 minutes"). The skill
   emits an interactive prompt with the expected outcome, waits for
   the operator's `pass` / `fail` / `blocked` response, and records
   the answer + free-text notes.
3. **`probe`** — a read-only call the skill makes itself (HTTP GET,
   status page check, metric query). Useful for "system is up"
   preconditions.

Every step result is recorded in `per-step.jsonl` as it executes —
one JSON object per line — so a crash mid-run still leaves the
partial log in a parseable state. See `references/report-schema.md`
for the exact shape.

### Step 5 — Halt policy
The default halt policy is **"halt the scenario on any P0 step
failure; continue to the next scenario"**. Scenarios are independent;
one broken scenario does not mask coverage for the rest.

Non-default overrides come from `test-strategy.md`:

- `haltOn: firstFailure` — stop the whole run at the first fail, even
  non-P0. Used when dependent scenarios share state.
- `haltOn: criticalFailure` (default) — described above.
- `haltOn: never` — run everything, collect all failures, decide
  later. Used for discovery-phase runs.

A scenario that gets halted mid-walk marks its remaining steps as
`not-reached` (not `skipped` — skipped implies a decision, while
not-reached just means the run aborted). The distinction matters for
downstream accounting.

### Step 6 — Evidence requirements
For every step with status `failed`:

- **automated step** — screenshot mandatory, runner stdout/stderr
  captured, console log captured
- **human step** — operator note is mandatory; the prompt refuses to
  accept `fail` without a non-empty reason
- **probe step** — HTTP status + response body (truncated to 2KB)
  captured

If any failed step lacks evidence after Step 4 completes, the run
fails its own gate: `evidenceMissing > 0` blocks the report from
being written as `finalized`. It's written as `partial` with a WARNING
banner, and downstream consumers know to treat it as unreliable.

### Step 7 — Write outputs

1. **`.vibeflow/reports/uat-raw-report.md`** — the summary report in
   Markdown, consumed by `test-result-analyzer` / `observability-analyzer`
   / `release-decision-engine`. Schema frozen in
   `references/report-schema.md`; drift is a breaking change.
2. **`.vibeflow/artifacts/uat/<runId>/per-step.jsonl`** — the raw
   event log, written incrementally during the run. Kept forever.
3. **`.vibeflow/artifacts/uat/<runId>/screenshots/`** — one PNG per
   failed automated step, named `<scenarioId>-<stepIndex>.png`.
4. **`.vibeflow/artifacts/uat/<runId>/final-state.json`** — a
   serialized snapshot of the env probe results at run completion,
   so post-mortems can diff state.

## Output Contract

### `uat-raw-report.md`
```markdown
# UAT Raw Report — <runId>

## Header
- Run id: <runId>
- Env: staging (https://staging.example.com)
- Started: 2026-04-13T12:00:00Z
- Finished: 2026-04-13T12:14:32Z
- Operator: ci / <username>
- Scenario set: scenario-set.md@<gitSha>
- Executor: uat-executor@0.1.0
- Finalization: finalized | partial:<reason>

## Summary
- Scenarios executed: N
- P0 scenarios executed: a / b (a must equal b to be gate-passing)
- Passed: p
- Failed: f
- Blocked: b
- Not reached (halted): nr
- Skipped (non-interactive): sni
- evidenceMissing: 0

## Scenario results
### SC-112: user completes checkout (P0) — PASSED
- Duration: 14.2s
- Steps: 7 passed, 0 failed
- Evidence: `screenshots/SC-112-*.png` (none captured — happy path)

### SC-113: user sees error on expired coupon (P0) — FAILED
- Duration: 6.8s
- Failing step: #3 (automated) — "apply expired coupon"
- Error: expected `.coupon-error` visible; got 404 on /api/coupons
- Evidence: `screenshots/SC-113-3.png`, `per-step.jsonl#L42-L58`
- Halted: yes (P0 rule)

## Per-step log
<excerpt or link to per-step.jsonl>

## Notes
- <free-text notes from operator, if any>
```

## Gate Contract
**Every failed step carries evidence, every P0 scenario is executed,
no step is marked `passed` without a recorded assertion.** These
three invariants are the reason downstream consumers can trust the
report at all.

Verdict rules:

| Condition | Verdict |
|-----------|---------|
| `evidenceMissing == 0 && p0Executed == p0Total && failedWithoutAssertion == 0` | finalized |
| Any of the above fails | partial (WARNING header, downstream should discount) |

Non-interactive (CI) runs with `skipped-noninteractive` on any P0
human step → partial. A P0 scenario that depends on human observation
cannot be gate-passed by the skill alone.

## Non-Goals
- Does NOT generate scenarios (`test-strategy-planner`) or tests
  (`e2e-test-writer`).
- Does NOT modify the test environment beyond what scenarios
  explicitly drive. UAT is observation, not remediation.
- Does NOT make the release decision — it produces raw material,
  and `release-decision-engine` decides.
- Does NOT retry failed steps. Flake detection is owned by
  observability's `ob_track_flaky` tool; UAT reports what happened.
- Does NOT run against production. There is no override flag.

## Downstream Dependencies
- `test-result-analyzer` — parses `uat-raw-report.md` into a classified
  failure set
- `observability-analyzer` — reads timing data from the per-step log
  to feed `ob_perf_trend`
- `release-decision-engine` — reads the `Summary` block as a hard
  blocker signal (`evidenceMissing > 0` OR `partial` finalization
  blocks GO)
- `traceability-engine` — links scenario ids ↔ PRD anchors via the
  same `SC-xxx` / `BR-xxx` scheme used elsewhere
