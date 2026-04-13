# Pipelines

VibeFlow ships with **7 canonical pipelines**. Each is a fixed sequence
of skills with explicit gates between steps. Pipelines are the
coarse-grained unit of work — you pick one, it runs, every step's
output feeds the next step. This document is the human-friendly
version of `skills/_standards/orchestrator.md`.

For the JSON-precise step definitions (input keys, gate conditions,
parallel blocks), read `skills/_standards/orchestrator.md` directly.

## Pipeline decision tree

```
Are you starting a new feature from a PRD?
├── yes → PIPELINE-1 (New Feature Development)
└── no →
    │
    Are you opening a PR or pushing a code change?
    ├── yes → PIPELINE-2 (Pre-PR / Code Review)
    └── no →
        │
        Is the build being promoted to staging for UAT?
        ├── yes → PIPELINE-3 (Staging / UAT)
        └── no →
            │
            Are you making a GO/CONDITIONAL/BLOCKED call for release?
            ├── yes → PIPELINE-4 (Release Decision)
            └── no →
                │
                Is this a production hotfix?
                ├── yes → PIPELINE-5 (Hotfix)
                └── no →
                    │
                    Is this the scheduled weekly learning review?
                    ├── yes → PIPELINE-6 (Weekly Learning)
                    └── no →
                        │
                        Did you receive production feedback about a bug?
                        └── yes → PIPELINE-7 (Production Feedback)
```

---

## PIPELINE-1 — New Feature Development

**When**: a new PRD lands or a feature branch opens
**Trigger**: `new_prd` / `feature_branch_opened`
**Phase**: REQUIREMENTS → PLANNING

```
┌────────────────────────────────────────────────────────────────┐
│  1. prd-quality-analyzer                                       │
│     gate: testabilityScore ≥ 60 (80 for financial/healthcare)  │
│     fail → STOP: rewrite the PRD                               │
└───────────────┬────────────────────────────────────────────────┘
                ▼
┌────────────────────────────────────────────────────────────────┐
│  2. architecture-validator                                     │
│     gate: criticalPolicyViolations == 0                        │
│     fail → STOP: redesign or override via ADR                  │
└───────────────┬────────────────────────────────────────────────┘
                ▼
┌────────────────────────────────────────────────────────────────┐
│  3. test-strategy-planner → scenario-set.md + test-strategy.md │
└───────────────┬────────────────────────────────────────────────┘
                ▼
┌───── step 4: PARALLEL (all four run concurrently) ─────────────┐
│   component-test-writer    contract-test-writer                │
│   business-rule-validator  test-data-manager                   │
└───────────────┬────────────────────────────────────────────────┘
                ▼
┌────────────────────────────────────────────────────────────────┐
│  5. traceability-engine → rtm.md                               │
│     gate: every P0 requirement has at least one test row      │
└────────────────────────────────────────────────────────────────┘
```

**Typical runtime**: 3-10 minutes depending on PRD size. The
parallel step 4 is the wall-clock dominator.

---

## PIPELINE-2 — Pre-PR / Code Review

**When**: a PR opens or a push lands
**Trigger**: `pr_opened` / `push`
**Phase**: DEVELOPMENT

```
┌──── 1. test-priority-engine ──────────────────────────────────┐
│     reads changed files + regression-baseline                 │
│     emits priority-plan.md (quick/smart/full)                 │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. regression-test-runner ────────────────────────────────┐
│     gate: P0 pass rate == 100% (no tolerance)                 │
│     fail → BLOCK: fix the regression before merge             │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. checklist-generator (context=pr-review) ───────────────┐
│     emits checklist-pr-review-<platform>-<ISO>.md             │
│     gate: zero unverifiable items                             │
└───────────────────────────────────────────────────────────────┘
```

PIPELINE-2 is the fastest pipeline — typical runtime 30s-2min
depending on the `--mode` argument on `test-priority-engine` (quick
/ smart / full).

---

## PIPELINE-3 — Staging / UAT

**When**: a build is promoted to staging
**Trigger**: `deploy_staging` / `manual_uat`
**Phase**: DEVELOPMENT → TESTING

```
┌──── 1. e2e-test-writer ───────────────────────────────────────┐
│     reads scenario-set.md → generates .spec.ts files          │
│     gate: zero raw selectors, zero sleep waits                │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. environment-orchestrator ──────────────────────────────┐
│     gate: healthcheck per component, teardown per setup       │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. uat-executor ──────────────────────────────────────────┐
│     gate: every P0 scenario executed, every failure has       │
│           evidence attached                                   │
└──────┬────────┬──────────────┬──────────────┬─────────────────┘
       ▼        ▼              ▼              ▼
┌── 4 reconciliation-simulator (financial-only) ────────────────┐
│     gate: zero invariant violations, deterministic replay     │
└───────────────┬───────────────────────────────────────────────┘
       ▼        ▼              ▼              ▼
┌── 5 test-result-analyzer   ┌── 6 chaos-injector ──────────────┐
│   → bug-tickets.md         │  gate: gentle-profile survives   │
└──────┬─────────────────────┴──────────────┬───────────────────┘
       ▼                                    ▼
┌── 7 cross-run-consistency  ┌── 8 observability-analyzer ──────┐
│   P0: strict 3/3 runs      │  gate: web vitals meet budget    │
└──────┬─────────────────────┴──────────────┬───────────────────┘
       ▼                                    ▼
       └─────────── 9. visual-ai-analyzer ──┘
                    gate: zero critical P0 regressions
```

Steps 5-9 run after uat-executor and mostly in parallel. The
reconciliation-simulator (step 4) only runs when `domain ==
"financial"`; every other domain skips it.

---

## PIPELINE-4 — Release Decision

**When**: the team is ready to make a GO/CONDITIONAL/BLOCKED call
**Trigger**: manual (`/vibeflow:release-decision-engine`)
**Phase**: TESTING → DEPLOYMENT

```
┌──── 1. release-decision-engine ───────────────────────────────┐
│     reads every L1/L2 report in .vibeflow/reports/            │
│     computes the weighted composite for the project's domain  │
│     applies hard-block rules                                  │
│     emits release-decision.md with verdict                    │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. decision-recommender (conditional) ────────────────────┐
│     Runs only if the verdict is CONDITIONAL or BLOCKED.       │
│     Emits decision-package.md with options (every option has  │
│     positive + negative + unknown tradeoffs, OPT-0 is always  │
│     "Do Nothing").                                            │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. checklist-generator (context=release) ─────────────────┐
│     Emits release checklist for human signoff.                │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 4. dev-ops.do_trigger_pipeline (on GO) ───────────────────┐
│     Fires the CI/CD deployment pipeline via the dev-ops MCP.  │
└───────────────────────────────────────────────────────────────┘
```

The weighted composite formula + domain thresholds are documented
in [docs/SKILLS-REFERENCE.md](./SKILLS-REFERENCE.md#release-decision-engine).

---

## PIPELINE-5 — Hotfix

**When**: a production incident needs a fast fix
**Trigger**: `hotfix_branch_opened` / `p0_incident`
**Phase**: DEVELOPMENT (bypasses normal phase gates)

```
┌──── 1. test-priority-engine (--mode smart) ───────────────────┐
│     Focused on the changed files + every P0 test.             │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. regression-test-runner ────────────────────────────────┐
│     gate: P0 100% (same as PIPELINE-2)                        │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. release-decision-engine (expedited) ───────────────────┐
│     Same gates as PIPELINE-4 step 1, but the CONDITIONAL band │
│     auto-approves given the production incident context.     │
└────────────────────────────────────────────────────────────────┘
```

PIPELINE-5 is the fastest path to production — typical runtime
2-5 minutes. It deliberately skips UAT and chaos testing on the
theory that the alternative (a longer production outage) is worse.
A hotfix ALWAYS triggers a follow-up PIPELINE-6 run to add the
incident to the learning loop.

---

## PIPELINE-6 — Weekly Learning

**When**: scheduled (typically end-of-sprint or weekly)
**Trigger**: `cron` / manual
**Phase**: any (read-only, advisory)

```
┌──── 1. test-result-analyzer (aggregate mode) ─────────────────┐
│     Reads every regression-baseline.json from the window.     │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. learning-loop-engine (test-history mode) ──────────────┐
│     Detects flaky-test clusters, time-to-fix trends, coverage │
│     drift. Emits learning-report.md.                          │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. decision-recommender ──────────────────────────────────┐
│     Turns learning findings into option packages with         │
│     tradeoffs for the team's next retrospective.              │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 4. coverage-analyzer (trend mode) ────────────────────────┐
│     Emits coverage-trend.md showing week-over-week deltas.    │
└────────────────────────────────────────────────────────────────┘
```

PIPELINE-6 is **advisory** — nothing it produces can merge-block a
change. Its output is read in retrospective meetings and fed back
into `test-strategy.md` for the next sprint.

---

## PIPELINE-7 — Production Feedback

**When**: a production bug is reported or observed
**Trigger**: manual (`/vibeflow:learning-loop-engine production-feedback`)
**Phase**: any (read-only, advisory)

```
┌──── 1. Intake ────────────────────────────────────────────────┐
│     Human enters a production bug description.                │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 2. learning-loop-engine (production-feedback mode) ───────┐
│     Cross-references the bug against existing test patterns.  │
│     Flags novel bugs (no matching pattern) for urgent review. │
│     Gate: every production bug traces OR is flagged novel.    │
└───────────────┬───────────────────────────────────────────────┘
                ▼
┌──── 3. decision-recommender ──────────────────────────────────┐
│     Produces a decision package with options: add-test /      │
│     change-invariant / adjust-threshold / Do-Nothing.         │
└───────────────────────────────────────────────────────────────┘
```

PIPELINE-7 is the feedback loop that keeps the test suite honest.
Novel production bugs (bugs with no matching test pattern) are the
most actionable outputs — they identify an invariant the team hasn't
formalized yet.

---

## Solo vs team mode — which pipelines are enabled

| Pipeline | Solo | Team |
|----------|------|------|
| PIPELINE-1 (new feature) | ✅ | ✅ |
| PIPELINE-2 (pre-PR) | ✅ | ✅ |
| PIPELINE-3 (staging UAT) | ⚠️ reduced (no 3-AI review at step 3) | ✅ full |
| PIPELINE-4 (release decision) | ⚠️ reduced (single-AI verdict) | ✅ full |
| PIPELINE-5 (hotfix) | ✅ | ✅ |
| PIPELINE-6 (weekly learning) | — (optional) | ✅ |
| PIPELINE-7 (production feedback) | ✅ | ✅ |

The `defaultPipeline` field in `vibeflow.config.json` controls
which pipeline `/vibeflow:run-pipeline` invokes when no explicit
pipeline is passed.

## Running a pipeline end-to-end

```
/vibeflow:run-pipeline new-feature
```

Alternatively, invoke the skills in sequence by hand (useful for
debugging a specific step):

```
/vibeflow:prd-quality-analyzer docs/PRD.md
/vibeflow:architecture-validator docs/adr/
/vibeflow:test-strategy-planner docs/PRD.md
/vibeflow:component-test-writer src/my-module.ts
/vibeflow:traceability-engine
```

Both paths produce the same reports. The difference is that the
pipeline-level invocation enforces the step gates automatically
(you stop at step 2 if `criticalPolicyViolations > 0`), while the
hand-run path lets you skip / reorder.
