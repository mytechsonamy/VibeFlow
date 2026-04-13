---
name: learning-loop-engine
description: Consumes the full history of reports from every L2 skill, detects recurring patterns, traces production bugs back to missed test opportunities, detects quality drift across sprint baselines, and recommends the next maturity-stage improvements. Operates in three modes — test-history / production-feedback / drift-analysis — each with its own pattern-detection flow. Gate contract — every recommendation must be actionable, every pattern must carry ≥ 3 supporting observations, every production bug must trace to a specific test gap or be marked irreducible with justification. PIPELINE-6 step 1 / PIPELINE-7 step 1.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Learning Loop Engine

An L3 Truth-Evolution skill. Where every L2 skill looks at a
SINGLE run and says "here's what's wrong right now", this
skill looks across TIME and says "here's the pattern, here's
what it's been costing you, here's what to change". The
output isn't a gate verdict; it's an improvement plan.

L3 skills are the slow loop. They run once per sprint (or on
demand when a production incident needs a post-mortem), they
take longer, and they produce recommendations the team
evaluates rather than gate-blocks on. A team that runs
learning-loop-engine weekly tends to catch structural quality
drift months earlier than a team that only runs per-release
gates — that's the bet L3 is making.

## When You're Invoked

- **PIPELINE-6 step 1** — first step of the release pipeline,
  before the release gate runs. Surfaces recurring patterns
  the release decision should know about (not block on —
  L3 recommendations are informational to the gate).
- **PIPELINE-7 step 1** — first step of the retrospective
  pipeline. Runs on demand at sprint boundaries.
- **On demand** as
  `/vibeflow:learning-loop-engine [--mode <m>] [--since <sha>]`.
- **From `release-decision-engine`** when a post-release
  incident needs the "what did we miss" trace.

## Input Contract

The skill runs in one of three distinct modes. Each mode has
its own input contract.

### Mode 1: `test-history`
Default mode. Analyzes the project's accumulated test reports.

| Input | Required | Notes |
|-------|----------|-------|
| `regression-baseline.json` | yes | Current + historical (from `.vibeflow/artifacts/regression/baseline-history/`) |
| `bug-tickets.md` | optional but preferred | From `test-result-analyzer` |
| `mutation-report.md` history | optional | From `mutation-test-runner` |
| `consistency-report.md` history | optional | From `cross-run-consistency` |
| `coverage-report.md` history | optional | From `coverage-analyzer` |
| Sprint window | optional | `--sprint <N>` limits the window; default: last 3 sprints |

### Mode 2: `production-feedback`
Traces a real production bug back to its test gap.

| Input | Required | Notes |
|-------|----------|-------|
| Production bug report | yes | Markdown with title + description + affected features + reproduction |
| Scenario set | yes | `scenario-set.md` to search for "should have caught this" scenarios |
| RTM | yes | `rtm.md` to walk requirement → scenario → test |
| Bug history | optional | Previous `learning-loop-engine` production traces to find duplicates |

### Mode 3: `drift-analysis`
Compares multiple baselines across sprints to detect degrading trends.

| Input | Required | Notes |
|-------|----------|-------|
| Baseline series | yes | At least 3 baselines from different sprints (from `.vibeflow/artifacts/regression/baseline-history/`) |
| Coverage series | optional | Matching coverage snapshots across the same sprints |
| Mutation series | optional | Matching mutation scores across the same sprints |

**Hard preconditions** — refuse rather than emit recommendations
the team should ignore:

1. The selected mode must have its required inputs. A run
   with `--mode drift-analysis` and only one baseline blocks
   with "drift analysis needs at least 3 baselines; got 1".
2. Every pattern the skill surfaces must have ≥ 3 supporting
   observations. A "recurring" pattern with only 2 hits
   isn't a pattern, it's a coincidence. The skill discards
   lower-support patterns at Step 4.
3. `production-feedback` mode REQUIRES the RTM to be
   up-to-date. An RTM with ≥ 10% drift (from
   `traceability-engine`) blocks production-feedback mode
   with "fix RTM drift first; tracing production bugs
   through a stale matrix produces wrong recommendations".

## Algorithm

### Step 1 — Resolve the mode
The `--mode` flag selects the mode. Default is
`test-history` when no mode is passed. A mode whose required
inputs are missing blocks at the precondition stage, not
silently.

Multi-mode runs are NOT supported — the three modes have
different output shapes, and a unified report would average
their signals in a way that loses detail. Run the skill once
per mode.

### Step 2 — Load the pattern catalog
Read `references/pattern-detection.md`. The catalog declares
patterns per mode:

- **test-history patterns** — recurring-failure, same-file-bug,
  taxonomy-drift, priority-drift, flake-concentration
- **production-feedback patterns** — covered-but-not-asserted,
  scenario-exists-not-tested, gap-in-scenario-set,
  irreducible
- **drift-analysis patterns** — coverage-decay, mutation-decay,
  flake-growth, priority-inflation, gate-suppression-creep

Every pattern entry in the catalog carries:
- `id` — stable identifier cited in reports
- `mode` — which of the three modes it applies to
- `signature` — how to detect it from the available inputs
- `minObservations` — the evidence floor (always ≥ 3)
- `severity` — `recommend` / `investigate` / `urgent`
- `remediation` — the concrete action the report should
  suggest

The skill is FORBIDDEN from inventing patterns at prompt
time. A finding that doesn't match any catalog entry lands
in `UNCLASSIFIED-LEARNING`, and a run with > 20% of findings
unclassified blocks (same taxonomy-gap rule as every other
L2/L3 taxonomy).

### Step 3 — Detect patterns
Walk the pattern catalog for the current mode. For each
pattern, evaluate its signature against the loaded inputs.
Every match is recorded as a `Finding`:

```ts
interface LearningFinding {
  id: string;
  patternId: string;         // from the catalog
  mode: "test-history" | "production-feedback" | "drift-analysis";
  observations: number;       // how many data points support this
  confidence: number;         // 0..1, from the pattern's confidence hints
  severity: "recommend" | "investigate" | "urgent";
  evidence: readonly string[]; // pointers to the supporting runs / reports / tickets
  rationale: string;          // why this pattern matters
  recommendation: string;     // concrete action
  affectedArtifacts: readonly string[]; // which test files / scenarios / PRD sections
}
```

Patterns with `observations < minObservations` are SKIPPED —
the skill doesn't make a weak recommendation loud. Skipped
patterns are still recorded in the artifact so a future run
can see "we were close last time".

### Step 4 — Deduplicate patterns across sprints
A pattern that surfaced in a previous learning-loop run with
the same signature is NOT surfaced again as "new". Instead:

- The previous finding is updated with a new `lastObservedAt`
- The `observations` counter grows
- The report shows it under "Recurring (seen N sprints)" so
  the team can see how long the pattern has been ignored

This is the learning-loop's memory — it remembers what it's
said before. Recommendations that have been shown 5 sprints
in a row with no remediation escalate their severity from
`recommend` to `investigate` to `urgent`, so the signal
climbs until the team acts on it.

Dedup key: `patternId :: affectedArtifactsHash`.

### Step 5 — Compute per-mode outputs

#### test-history output

For every pattern with ≥ 3 observations:

- Name the recurring failure shape
- Link to the supporting runs / tickets
- Suggest the specific fix ("add a test for X scenario",
  "tighten the W gate", "promote Y test to P0")

#### production-feedback output

For the production bug:

1. Extract the affected features from the bug description
2. Walk the RTM to find scenarios mapped to those features
3. Check `scenario-set.md` for scenarios that SHOULD have
   caught this bug but didn't
4. Classify the test gap:
   - `covered-but-not-asserted` — a test exists and runs
     the affected code but doesn't assert on the specific
     thing the bug broke
   - `scenario-exists-not-tested` — the scenario describes
     the bug's path but no test implements it
   - `gap-in-scenario-set` — no scenario covers this path;
     the PRD + scenario-set missed the case
   - `irreducible` — the bug is a class of problem the
     test framework fundamentally can't catch (race
     condition that only appears at production load,
     vendor library bug). ONLY classifiable after the
     skill walks every other option and none matches; the
     report surfaces this with a `requiresJustification`
     flag so a human signs off
5. Emit the specific remediation: which test to write,
   which scenario to extend, which assertion to tighten

A bug classified `irreducible` with no justification is
rejected at the recommendation step — the skill writes a
finding but marks it `needs-human-review: true` instead
of auto-promoting to the report.

#### drift-analysis output

For each signal series (coverage, mutation, flake count):

1. Compute the slope over the window (linear regression
   on the data points)
2. Compare against the signal's declared floor / ceiling
3. Emit a `drift` finding when:
   - Slope is in the wrong direction (coverage trending
     down, mutation score trending down, flake count
     trending up)
   - Magnitude exceeds the "noise floor" (minor fluctuation
     is expected; the skill ignores drift below 1% per
     sprint)

See `references/pattern-detection.md` §3 for the exact
slope + noise-floor formulas.

### Step 6 — Compute the maturity stage
Read `references/maturity-stages.md` and evaluate the
project against each stage's promotion criteria:

- **Stage 1 — Ad hoc** — no baselines, no classifications,
  tests exist but no structural gate
- **Stage 2 — Baseline** — at least one full regression
  baseline, gates on P0 pass rate
- **Stage 3 — Coverage** — mutation + coverage thresholds
  enforced, RTM populated
- **Stage 4 — Learning** — learning-loop-engine runs
  regularly, drift analysis catches real regressions
- **Stage 5 — Self-improving** — recommendations from L3
  skills are being acted on, measured improvement across
  sprints

Each stage has a list of promotion criteria. The skill
computes the highest stage whose criteria ALL pass, and
surfaces the NEXT stage's unmet criteria as the
recommended next step.

Stages are the "north star" view — the report's summary
section shows current stage + next stage + the specific
criteria blocking promotion.

### Step 7 — Apply the gate

The learning-loop-engine gate is informational, not
merge-blocking. The gate defines whether the report is
`actionable` or `degraded`:

| Condition | Report status |
|-----------|---------------|
| ≥ 3 findings with severity `urgent` AND actionable remediation | `actionable` |
| Between 1-2 urgent findings OR ≥ 5 recommend/investigate | `actionable` |
| All findings below minObservations OR all findings are irreducible | `degraded` — "not enough signal for recommendations" |
| > 20% of findings unclassified | `degraded` — "taxonomy gap" |

A `degraded` report is still emitted, but with a banner
that downstream consumers (`release-decision-engine`) can
read: "this week's learning loop produced no actionable
signal; don't weigh it into the gate".

### Step 8 — Write outputs

1. **`.vibeflow/reports/learning-report.md`** — human-
   readable summary with recommendations grouped by severity
2. **`.vibeflow/artifacts/learning/<runId>/findings.json`**
   — every finding including below-threshold ones, for the
   cross-run dedup in Step 4
3. **`.vibeflow/artifacts/learning/history.jsonl`** —
   append-only history with one event per finding
   (`created`, `recurring`, `resolved`). Never rewrite.

## Output Contract

### `learning-report.md`
```markdown
# Learning Loop Report — <runId>

## Header
- Run id: <runId>
- Mode: test-history | production-feedback | drift-analysis
- Window: last 3 sprints (since <date>)
- Inputs loaded: N reports, M baselines
- Report status: actionable | degraded (reason)
- Maturity stage: 3 (Coverage) → targeting 4 (Learning)

## Urgent recommendations
### LEARNING-RECURRING-FAILURE — SC-112 fails in 4/5 recent sprints
- Pattern: recurring-failure
- Observations: 4 (over 5 sprints, ~3 weeks between sprints)
- Severity: urgent (escalated from recommend after 3 sprints unresolved)
- Evidence:
  - regression-baseline.json@sprint-39: FAIL
  - regression-baseline.json@sprint-40: FAIL
  - regression-baseline.json@sprint-41: FAIL
  - regression-baseline.json@sprint-42: FAIL
- Rationale: SC-112 is P0, and a P0 scenario that keeps
  failing in baseline means either the test is wrong, the
  feature is perma-broken, or the baseline is lying
- Recommendation: run `cross-run-consistency` on SC-112
  this sprint; if it's non-deterministic, drop its P0
  tag; if it's deterministic, fix the SUT or replace the
  test

## Investigate
### LEARNING-FLAKE-CONCENTRATION — 6 tests concentrate 80% of flakes
- Pattern: flake-concentration
- Observations: 6 tests over 3 sprints
- Severity: investigate
- Evidence: [6 test ids + their flake scores]
- Rationale: flake concentration in a few tests usually
  indicates shared-state or shared-environment bugs, not
  widespread infra trouble
- Recommendation: audit the 6 tests' fixtures; likely a
  shared mock / shared fixture / shared database state

## Drift findings (only when drift-analysis mode)
### LEARNING-COVERAGE-DECAY — line coverage down 3.4% over 3 sprints
- Signal: line-coverage
- Slope: -1.1% per sprint
- Current: 0.82
- Target: 0.85 (domain threshold, slipping toward close-miss)
- Recommendation: identify the files that dropped; the
  drop is probably concentrated, not spread

## Maturity stage
- Current: Stage 3 (Coverage)
- Next: Stage 4 (Learning)
- Blocking criteria for promotion:
  - [x] Mutation test threshold enforced
  - [x] Coverage threshold enforced
  - [ ] Learning-loop report is acted on in 2+ sprints
  - [ ] Drift analysis catches real regressions
- Recommendation: commit to reading this report weekly;
  fix the urgent findings within the sprint they appear

## Skipped findings (below evidence threshold)
- LEARNING-PATTERN-X: 2 observations (needs 3)
- LEARNING-PATTERN-Y: 1 observation (needs 3)
```

## Gate Contract
**Three invariants that keep the learning loop honest:**

1. **Every pattern must have ≥ 3 supporting observations.**
   Weaker patterns aren't patterns; they're coincidences.
   The skill discards them at Step 3 rather than emitting
   noisy recommendations.
2. **Every production bug must trace to a specific test gap
   OR be explicitly `irreducible` with human justification.**
   A production bug with no explanation is a bug the skill
   doesn't understand, and recommending on a bug we don't
   understand is how the team starts mistrusting the loop.
3. **Every recommendation must be actionable.** "Improve
   tests" is not a recommendation; "run cross-run-consistency
   on SC-112 and drop its P0 tag if it's non-deterministic"
   is. Recommendations that fail the actionability check at
   review time are rejected.

Unlike the L2 skills, these invariants don't produce BLOCKED
verdicts — they produce `degraded` reports that downstream
can discount. The learning loop is advisory; teams opt into
acting on it.

## Non-Goals
- Does NOT make release decisions. That's
  `release-decision-engine`. The learning loop is advisory.
- Does NOT fix tests. It recommends; humans act.
- Does NOT replace retrospectives. Retros are for humans
  talking to humans; the loop is one more input into the
  retro.
- Does NOT emit every possible finding. The evidence floor
  (≥ 3 observations) is intentional — a noisy report is
  a useless report.
- Does NOT persist findings across project reclones. The
  history file is append-only per repo; a fresh clone
  starts with no memory. Teams that want long-term memory
  keep the history file in git.

## Downstream Dependencies
- `release-decision-engine` — reads `findings.json` with a
  `read-only advisory` weight. Findings never block a
  release by themselves; they feed the weighted quality
  score as one input of many.
- `decision-recommender` — ingests recommendations and
  ranks them for the team's next sprint.
- `traceability-engine` — uses the production-feedback
  output to patch RTM gaps that the bug revealed.
