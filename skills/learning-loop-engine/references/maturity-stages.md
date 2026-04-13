# Maturity Stages

A five-stage model the `learning-loop-engine` skill uses at
Step 6 of its algorithm to tell teams where they are in the
VibeFlow maturity journey and what to do next. Every report
names the current stage and the next stage's blocking
criteria.

Stages are observational, not aspirational. A project is at
Stage N when it meets ALL the criteria for Stage N AND at
least one criterion for Stage N+1 is not yet met. There's no
half-stage — a single unmet criterion keeps a project at the
previous stage, which keeps the promotion signal loud.

---

## Stage 1 — Ad hoc

### What it looks like

The project has tests, but they're not structured for gating.
Results are read by humans in a terminal; failures trigger
"figure it out" instead of "run the analyzer". `regression-
baseline.json` doesn't exist. The `vibeflow:` skill set isn't
running in any pipeline.

### Promotion criteria

To move from Stage 1 to Stage 2:

- [ ] `regression-baseline.json` exists and is promoted at
      least once via `regression-test-runner` with a PASS
      verdict
- [ ] At least one test is tagged `@priority P0`
- [ ] A first baseline passes the basic gate
      (`P0 pass rate == 1.0`)
- [ ] `vibeflow.config.json` declares the project's domain
      and source / test directories
- [ ] The P0 gate contract from `regression-test-runner` is
      actively enforced (a failing P0 on a PR actually blocks)

### Typical duration

A team moving from "we have tests" to Stage 2 usually takes
one sprint to wire the baseline + one sprint for the habits
to settle in. Teams that try to leap past Stage 2 to Stage 3
usually regress when the first real outage exposes the
missing foundation.

---

## Stage 2 — Baseline

### What it looks like

Regression baselines are being promoted regularly. The P0
gate blocks merges when it fails. Coverage exists as a metric
but isn't gated. Mutation score may or may not exist.
Flakiness is tracked in people's heads, not in a report.

### Promotion criteria

To move from Stage 2 to Stage 3:

- [ ] `mutation-test-runner` has been invoked at least once,
      produces a real score, and the score is recorded in
      `mutation-baseline.json`
- [ ] `coverage-analyzer` has been invoked at least once,
      and the overall line coverage meets the domain
      threshold
- [ ] `rtm.md` exists with at least 80% of the PRD
      requirements mapped to scenarios
- [ ] `cross-run-consistency` has been run on the P0
      scenarios and the consistency score is ≥ 0.95
- [ ] The P0 gate has been triggered by a real regression
      at least once (proves the gate works, not just that
      it was installed)

### What Stage 2 still lacks

Stage 2 gates on "the tests that were passing still pass",
but nothing gates on "the tests actually test the right
thing". That's what Stage 3 adds.

---

## Stage 3 — Coverage

### What it looks like

Line coverage is gated against the domain threshold. Mutation
score is gated on P0 files (zero survivors). Cross-run
consistency is gated on P0 tests. The RTM is up-to-date
enough that `test-result-analyzer` can trace failures to
requirements. Learning-loop-engine hasn't run yet, or runs
sporadically.

### Promotion criteria

To move from Stage 3 to Stage 4:

- [ ] `learning-loop-engine` runs at least once per sprint
      in `test-history` mode
- [ ] The learning report is read by at least one person on
      the team in every sprint where it runs
- [ ] At least one recommendation from a learning report
      has been acted on (not just "read and ignored")
- [ ] `drift-analysis` has been run against the project's
      baseline history at least once
- [ ] The team has a designated owner for the learning-loop
      report (not necessarily the same person every sprint,
      but SOMEONE each sprint)

### Stage 3 → 4 is the hardest transition

Stage 3 → Stage 4 is where most projects plateau. The gates
are installed, the scores are green, and the team stops
looking at recommendations because "everything is fine". The
signal that a project is stuck at Stage 3 is that the
learning loop is producing the same recommendations sprint
after sprint without any being acted on. The escalation
rule in `pattern-detection.md` §1 was specifically designed
to make this plateau loud — urgent findings that recur for
5 sprints in a row are the symptom.

---

## Stage 4 — Learning

### What it looks like

The learning loop runs regularly. Recommendations are
prioritized alongside feature work in sprint planning. Drift
analysis catches degradations before they trip the gates.
Production bugs are routinely traced back to specific test
gaps, and those gaps are filled within 1-2 sprints.

### Promotion criteria

To move from Stage 4 to Stage 5:

- [ ] Over 3 consecutive sprints, no learning-loop urgent
      finding has been ignored (every urgent finding has
      either been resolved or explicitly rejected with a
      written rationale)
- [ ] The learning-loop report's `degraded` status has NOT
      triggered in the last 3 sprints (the team is
      producing enough signal for actionable output)
- [ ] A production bug has been traced end-to-end via
      `production-feedback` mode and the identified test
      gap has been filled
- [ ] Drift analysis has caught at least one real
      regression (slope-based warning that turned into a
      real fix)
- [ ] Maturity stage has been visibly used in sprint
      planning as a goal (not just read on the report)

### What separates Stage 4 from Stage 5

Stage 4 is "we act on recommendations when they're loud
enough". Stage 5 is "we act on recommendations proactively
because the loop is part of how we work". The distinction
isn't measurable — it's behavioural. Stage 5 is the
self-sustaining state where the quality improvements are
compounding instead of just not regressing.

---

## Stage 5 — Self-improving

### What it looks like

The learning loop is embedded in the team's weekly rhythm.
Recommendations from L3 skills are being acted on
proactively, not reactively. The project's quality metrics
are improving over time, not just holding steady.
Production incidents are rare, and the rare ones that
happen get traced to test gaps that the team chooses to
fill.

### There's no Stage 6

Stage 5 is the terminal state by design. Further improvement
from here is measured in specific quality signals (coverage,
mutation, flake rate, production incident rate) rather than
in "more gates". A project that tries to add more gates from
Stage 5 usually becomes brittle; the path from Stage 5
forward is to DELETE gates whose signal has been internalized
as team habit.

### Staying at Stage 5

Stage 5 is not stable by default. The signals that keep a
project here:

- Learning-loop runs every sprint without fail
- Urgent findings get resolved within the sprint they appear
- Gate suppression count stays flat or decreases over time
- Maturity stage evaluation stays at 5 for ≥ 6 consecutive
  sprints

A project that was at Stage 5 and regresses back to Stage 4
is a teachable moment — the learning loop will surface the
regression as a `LEARNING-MATURITY-DEMOTION` finding, and
the team reads why.

---

## Demotion rules

A project at Stage N can be demoted to Stage N-1 when:

- ANY criterion for Stage N is no longer met for ≥ 2
  consecutive sprints
- The learning-loop report has been `degraded` for ≥ 3
  consecutive sprints (signal shortage means the project
  is running blind at the current stage)

Demotion is a signal, not a punishment. The report surfaces
it as "this project has regressed from Stage N to Stage N-1"
and lists the specific criteria that broke. Teams that
notice the demotion early and act usually recover within
the next sprint; teams that ignore it keep demoting.

---

## Stage evaluation rules

- **Evaluate from the top.** Start at Stage 5 and walk down
  until ALL the criteria for a stage pass. That's the
  current stage.
- **Report the NEXT stage's unmet criteria.** The report's
  main purpose is to tell the team what to do next, so the
  report always shows the criteria blocking the next
  promotion — never the criteria of the current stage.
- **A single unmet criterion blocks promotion.** There is
  no partial credit. "4 out of 5 criteria met" means the
  stage isn't achieved.
- **Criteria are evaluated deterministically.** Every
  criterion in this file has a specific data source
  (baseline file exists, coverage threshold met, etc.)
  that the skill checks. No "vibe" criteria.

---

## Maturity stages version

**`maturityStagesVersion: 1`**

Bump rules: adding a stage, reordering stages, or changing
promotion criteria requires a retrospective on at least 3
real projects that would be re-classified. Silent edits
fail CI.
