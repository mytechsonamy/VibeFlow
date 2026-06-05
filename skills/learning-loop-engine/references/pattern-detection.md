# Pattern Detection

Every pattern `learning-loop-engine` can identify. The skill
walks this catalog at Step 3 of its algorithm. Patterns are
mode-scoped — a `test-history` pattern is ignored in
`drift-analysis`, and vice versa. Inventing a pattern at
prompt time is forbidden; unmatched findings land in
`UNCLASSIFIED-LEARNING` and are surfaced for human triage.

Every pattern has seven fields:

- **id** — stable identifier cited in reports
- **mode** — which of the four modes it applies to
- **signature** — the exact detection rule (what the skill
  looks for in the loaded inputs)
- **minObservations** — evidence floor (≥ 3, always)
- **severity** — `recommend` / `investigate` / `urgent`
- **rationale** — one-sentence "why this matters"
- **remediation** — the concrete action the report suggests

---

## 1. `test-history` mode patterns

### LEARNING-RECURRING-FAILURE
- **mode**: test-history
- **signature**: a single test fails in at least 3 of the
  last 5 baselines AND is marked `@priority P0` (or its
  scenario has `priority: P0`)
- **minObservations**: 3 (out of 5-baseline window)
- **severity**: `recommend` initially; escalates to
  `investigate` after 4/5 sprints unresolved; `urgent`
  after 5/5 sprints unresolved
- **rationale**: a P0 scenario that keeps failing in
  baseline is either a lying test, a perma-broken feature,
  or a broken baseline
- **remediation**: run `cross-run-consistency` on the
  scenario; if non-deterministic, drop the P0 tag; if
  deterministic, fix the SUT or replace the test

### LEARNING-SAME-FILE-BUG
- **mode**: test-history
- **signature**: ≥ 3 tickets in `bug-tickets.md` history
  reference the same source file (from their
  `evidence.stackTrace` or their title text)
- **minObservations**: 3 (distinct tickets, same file)
- **severity**: `investigate`
- **rationale**: a file that generates multiple bugs
  across sprints has a structural problem: complexity,
  unclear invariants, or insufficient tests
- **remediation**: mark the file for refactoring review;
  increase its mutation-test-runner priority; verify its
  coverage meets the domain floor

### LEARNING-TAXONOMY-DRIFT
- **mode**: test-history
- **signature**: ≥ 20% of classifications across the
  window are `UNCLASSIFIED-*` (from any L2 taxonomy —
  test-result-analyzer, cross-run-consistency,
  observability-analyzer, visual-ai-analyzer,
  mutation-test-runner)
- **minObservations**: 3 runs contributing > 20%
- **severity**: `urgent`
- **rationale**: taxonomy drift means the classification
  layer is missing signal; every downstream gate is
  operating on an incomplete picture
- **remediation**: extend the relevant taxonomy file
  with entries for the UNCLASSIFIED findings; the
  learning-loop report lists which taxonomies are the
  worst offenders

### LEARNING-PRIORITY-DRIFT
- **mode**: test-history
- **signature**: the count of `@priority P0` scenarios /
  files has grown by > 25% over the window AND no new
  features justify the growth in `scenario-set.md`
- **minObservations**: 3 sprints with monotonic growth
- **severity**: `investigate`
- **rationale**: P0 is the gate's strictest rule; over-
  tagging P0 makes every gate harder until teams start
  suppressing them. P0 inflation is how gate fatigue
  begins
- **remediation**: audit the P0 list; drop scenarios
  that don't meet the domain's P0 criteria (see
  `scenario-set.md`'s priority definitions)

### LEARNING-FLAKE-CONCENTRATION
- **mode**: test-history
- **signature**: > 80% of flakes reported by
  `ob_track_flaky` concentrate in < 10% of test files
- **minObservations**: 3 consecutive runs with the
  same concentration
- **severity**: `investigate`
- **rationale**: concentrated flakes usually indicate
  shared-state / shared-environment bugs, not widespread
  infrastructure trouble. Fix the concentration source
  and the flake rate drops across the board
- **remediation**: audit the top-N flaky files for shared
  mocks, shared fixtures, shared database state; the loop
  report names the specific files

---

## 2. `production-feedback` mode patterns

### LEARNING-COVERED-NOT-ASSERTED
- **mode**: production-feedback
- **signature**: the bug's affected code path IS executed
  by at least one existing test (per `ci_dependency_graph`)
  BUT the test's assertions don't check the specific
  property the bug violated
- **minObservations**: 1 (production-feedback patterns
  only need the single bug; the "observations" count is
  about HOW MANY test files exercise the path)
- **severity**: `urgent`
- **rationale**: this is the worst kind of coverage gap —
  the line coverage is fine, the mutation score might be
  fine, but the assertion doesn't catch the bug that
  actually shipped
- **remediation**: tighten the assertion in the
  specific test; list the test file + line + the exact
  assertion that should have caught this

### LEARNING-SCENARIO-EXISTS-NOT-TESTED
- **mode**: production-feedback
- **signature**: `scenario-set.md` contains a scenario
  that describes the bug's path, but no test file
  implements it (no `trace: scenarios/SC-xxx` comment
  anywhere in the test suite)
- **minObservations**: 1
- **severity**: `urgent`
- **rationale**: the team KNEW this path mattered enough
  to write a scenario for it, but the test never got
  written. Tactical fix, not a strategic one
- **remediation**: invoke `component-test-writer` /
  `e2e-test-writer` with the specific scenario id

### LEARNING-GAP-IN-SCENARIO-SET
- **mode**: production-feedback
- **signature**: no scenario in `scenario-set.md`
  describes the bug's path; the RTM has no requirement
  covering it
- **minObservations**: 1
- **severity**: `urgent`
- **rationale**: the PRD and scenario-set missed a case.
  Fix is upstream — extend the PRD if the requirement is
  new, extend the scenario set if the PRD covers it but
  scenario-set.md doesn't
- **remediation**: run `test-strategy-planner` with the
  production bug as an anchor; it'll generate the
  missing scenario

### LEARNING-IRREDUCIBLE
- **mode**: production-feedback
- **signature**: none of the above match after a full
  walk
- **minObservations**: 1
- **severity**: `investigate`
- **rationale**: a bug that doesn't map to any test gap
  is usually a class-of-problem issue: race conditions
  visible only under production load, vendor library
  bugs, hardware-dependent behaviour, unreproducible
  environmental issues
- **remediation**: **REQUIRES HUMAN JUSTIFICATION.** The
  skill writes the finding with `needs-human-review:
  true` and surfaces it in the report under "irreducible
  candidates". A human must sign off with a written
  rationale before the finding is accepted; reasonless
  irreducible classifications are rejected at read time
  by downstream consumers

---

## 3. `drift-analysis` mode patterns

### LEARNING-COVERAGE-DECAY
- **mode**: drift-analysis
- **signature**: line-coverage slope over the window is
  negative AND the slope's absolute value exceeds 1.0%
  per sprint (the noise floor)
- **minObservations**: 3 coverage snapshots
- **severity**: `recommend` initially; `investigate` when
  current coverage is within 2% of the domain floor;
  `urgent` when current coverage is below the domain
  floor
- **rationale**: coverage decay over sprints is how line
  coverage silently becomes a lie — tests get added but
  are out-paced by source additions
- **remediation**: identify the files that dropped most
  (from the per-file coverage series); the decay is
  probably concentrated, not spread

### LEARNING-MUTATION-DECAY
- **mode**: drift-analysis
- **signature**: mutation score slope over the window is
  negative AND the absolute slope exceeds 2.0% per
  sprint
- **minObservations**: 3 mutation snapshots
- **severity**: `investigate` unless within 5% of the
  domain floor (then `urgent`)
- **rationale**: mutation decay means the assertions
  aren't keeping up with the code; tests exist but don't
  actually test
- **remediation**: audit the top-regressing files via
  `mutation-test-runner`; most decay is concentrated in
  a few files that stopped being actively tested

### LEARNING-FLAKE-GROWTH
- **mode**: drift-analysis
- **signature**: count of tests classified `flaky` by
  `ob_track_flaky` has grown ≥ 50% over the window
- **minObservations**: 3 flakiness reports
- **severity**: `investigate` initially; `urgent` when
  flakes exceed 5% of the total test count
- **rationale**: flake growth compounds — each flake
  erodes trust in the suite, which makes real failures
  easier to ignore
- **remediation**: scheduled flake-cleanup sprint; the
  loop report names the top-N newest flakes

### LEARNING-GATE-SUPPRESSION-CREEP
- **mode**: drift-analysis
- **signature**: the total count of entries in
  `test-strategy.md` suppression lists
  (`visualSuppressions`, `observabilitySuppressions`,
  `ticketSeverityOverrides`, etc.) has grown ≥ 3 per
  sprint
- **minObservations**: 3 sprints of growth
- **severity**: `investigate`
- **rationale**: suppression creep means the team is
  tuning the gate around real failures instead of fixing
  them. Each suppression has a rationale, so they look
  justified individually — the pattern only shows up
  over time
- **remediation**: audit the suppressions that have
  been in place > 2 sprints; each should either be
  resolved (rationale fulfilled) or escalated (the
  problem is a real design decision, not a skipped
  fix)

---

## 4. `consensus-history` mode patterns

Read from `.vibeflow/state/consensus/history.jsonl` (Sprint 20-A).
`verdict` rows carry `{phase, primaryArtifact, round, status,
agreement, counts, reviewers, suggestionThemes}`; `arbiter-decision`
rows carry `{round, applied[], rejected[]}`. Window = last
`learningLoop.sprintWindow` sprints (default 3).

### LEARNING-SLOW-CONVERGING-PHASE
- **mode**: consensus-history
- **signature**: ≥ 3 sessions in the same `phase` whose maximum
  `round` before reaching `status: APPROVED` was > 1
- **minObservations**: 3 sessions
- **severity**: `investigate`
- **rationale**: a phase that repeatedly needs multiple review
  rounds is admitting low-quality artifacts to consensus; the cost
  is paid every sprint in extra rounds
- **remediation**: tighten the phase's entry artifact upstream
  (e.g. PRD acceptance criteria for REQUIREMENTS); the report names
  the phase and its dominant `suggestionThemes`

### LEARNING-REVIEWER-SKEW
- **mode**: consensus-history
- **signature**: one reviewer accounts for > 60% of `counts.critical`
  summed across the window
- **minObservations**: 3 sessions the reviewer participated in
- **severity**: `recommend`
- **rationale**: a reviewer holding most criticals is either the
  only one doing deep review (a bus-factor risk) or mis-calibrated
  (raising noise the others discount) — both are worth knowing
- **remediation**: investigate whether the skew is signal or noise;
  calibrate the reviewer prompt or rebalance the panel — never
  silence the reviewer automatically

### LEARNING-RECURRING-SUGGESTION-THEME
- **mode**: consensus-history
- **signature**: the same `suggestionThemes` value appears across
  ≥ 3 distinct `primaryArtifact`s in the window
- **minObservations**: 3 distinct artifacts
- **severity**: `investigate`
- **rationale**: a theme that recurs across unrelated artifacts is a
  systemic upstream gap (a PRD template, an ADR convention, a
  test-strategy default), not a per-artifact slip
- **remediation**: route to the upstream artifact owner — fix the
  template / convention once, not each artifact

### LEARNING-CONVERGENCE-STALL
- **mode**: consensus-history
- **signature**: ≥ 3 stall events — `convergence-stalled.md` /
  `max-iterations-reached.md` artifacts, or `verdict` rows where the
  session hit `consensus.maxIterations` without APPROVED
- **minObservations**: 3 stalls
- **severity**: `urgent`
- **rationale**: repeated stalls mean the iteration loop is grinding
  without converging — wasted reviewer rounds and a blocked phase
- **remediation**: raise `consensus.maxIterations`, escalate to the
  phase specialist earlier, or accept HUMAN_APPROVAL_REQUIRED with
  an audit note

### LEARNING-PRIMARY-ARTIFACT-CHURN
- **mode**: consensus-history
- **signature**: one `primaryArtifact` consumes an outlier number of
  total rounds across sessions (> 2× the per-artifact median over
  the window)
- **minObservations**: 3 sessions on the same artifact
- **severity**: `investigate`
- **rationale**: a single artifact eating disproportionate review
  effort usually means it is under-specified or contested, not that
  the reviewers are wrong
- **remediation**: schedule a focused rewrite via the phase
  specialist; the report names the artifact and its round history

### LEARNING-INEFFECTIVE-THEME
- **mode**: consensus-history (Sprint 20-C effectiveness trace)
- **signature**: a theme `applied` in an `arbiter-decision` row at
  round R is followed by an agreement delta
  (`verdict[R+1].agreement − verdict[R].agreement`) of ≤ 0.02 across
  ≥ 3 occurrences
- **minObservations**: 3 applied-then-no-movement occurrences
- **severity**: `investigate`
- **rationale**: applying suggestions of this type reliably fails to
  move agreement — the loop is grinding on cosmetic fixes while the
  substantive objection stands. This is the wasted-effort signal
- **remediation**: stop auto-applying the theme; route the
  underlying objection to a human or the phase specialist for a
  structural fix instead of another cosmetic patch

### LEARNING-AUTO-TUNE-INEFFECTIVE
- **mode**: consensus-history (Sprint 24-B meta-learning)
- **signature**: for a config key, count its `auto-apply` rows
  (Sprint 24-A) and how many were followed by an `auto-revert` (vs an
  `auto-apply-held`). Fires when `reverts ≥ 3` AND the revert rate
  (`reverts / auto-applies`) ≥ 0.5
- **minObservations**: 3 auto-apply attempts for the key
- **severity**: `investigate`; escalates to `urgent` as the revert
  count climbs
- **rationale**: the loop's own auto-tuning of this key keeps getting
  reverted — tuning it doesn't move agreement, so auto-applying it just
  burns a consensus round each sprint before the cooldown catches it
- **remediation**: remove the key from `autoApply.keys`
  (`vibeflow.config.json`). `learning-apply` already self-demotes it to
  propose-only after `autoApply.demoteAfterReverts` reverts (Sprint
  24-C); this finding recommends making that permanent

### LEARNING-CROSS-PROJECT-SIGNAL
- **mode**: consensus-history (Sprint 28-C — opt-in, read-only)
- **signature**: when `globalLearning.enabled`, read the shared
  `$(vf_global_dir)/global-learning.jsonl` (privacy-safe rows
  `{key, outcome, phase, projectHash}`). For each config key, count
  distinct `projectHash`es and the hold-rate
  `held / (held + reverted)`. Fires when the key appears in ≥ 3 distinct
  projects AND hold-rate ≥ 0.7 (positive) or ≤ 0.3 (negative)
- **minObservations**: 3 distinct projects
- **severity**: `recommend`
- **rationale**: a tune that reliably holds (or reverts) across many
  *independent* projects is a stronger signal than one project's local
  history — but it is still only advice; every project's config + domain
  differ
- **remediation**: **recommendation only.** Positive ⇒ "consider adding
  `<key>` to `autoApply.keys` (held in N/M projects)"; negative ⇒
  "avoid auto-applying `<key>` (reverted in N/M projects)". The detector
  **NEVER** auto-allowlists or auto-applies — one repo's record can't
  change another's behaviour. Privacy: only key/outcome/phase/projectHash
  ever leave a repo (no code, content, file names, or theme text)

---

## 5. Slope + noise-floor formulas

For every drift pattern, the skill computes slopes via
linear regression on the data points:

```
slope = Σ((x - x̄)(y - ȳ)) / Σ((x - x̄)²)
```

- `x` = sprint index (0, 1, 2, ..., N-1)
- `y` = the signal value (coverage, mutation score, flake
  count)
- `x̄`, `ȳ` = means

A slope is significant when `|slope| > noise_floor`, where
the noise floor is declared per signal:

| Signal | Noise floor |
|--------|-------------|
| line coverage | 1.0% / sprint |
| branch coverage | 1.5% / sprint |
| mutation score | 2.0% / sprint |
| flake count | 50% / sprint (flakes are noisy; the floor is intentionally high) |
| P0 scenario count | 25% / sprint |

Noise floors can only be TIGHTENED via `test-strategy.md →
driftNoiseFloors`. Loosening is rejected; a noise floor
over the default is how patterns stop surfacing.

---

## 6. Pattern catalog rules

- **Never delete a pattern.** Old reports reference these
  ids; deletion orphans them. Deprecate with
  `deprecated: true` instead.
- **Minimum-evidence is non-negotiable.** Every pattern
  requires ≥ 3 observations. A pattern that "would be
  useful even with 1 observation" is a pattern we don't
  trust. Rejected at review.
- **Severity is mode-scoped.** A test-history pattern's
  severity doesn't transfer to production-feedback mode.
  Each mode has its own severity band because the stakes
  differ (production feedback = real user impact, drift
  analysis = future risk, test-history = current drift).
- **Adding a new pattern requires a retrospective.** Show
  the pattern identifies real recurring problems in at
  least 5 historical runs before landing it in the
  catalog.

---

## 7. Current pattern catalog version

**`patternCatalogVersion: 4`**

- test-history patterns: 5
- production-feedback patterns: 4
- drift-analysis patterns: 4
- consensus-history patterns: 8 (Sprint 20-B / 20-C + Sprint 24-B auto-tune-ineffective + Sprint 28-C cross-project-signal)
- Minimum evidence: 3 observations per pattern
- Noise floors: declared per signal

Every report writes `patternCatalogVersion` in its header
so historical reports stay interpretable after catalog
updates.
