# Risk Model

The exact formula `test-priority-engine` uses to score every
candidate test at algorithm Step 3. The formula is deterministic
(same inputs → same score) and each component is auditable in the
output plan. If a test ranks surprisingly high or low, the
contributing-factors column in the plan should immediately explain
why.

This file is the single source of truth. The skill does NOT invent
components, and changes to any weight here must be backed by a
retrospective on real failure data — never a guess.

---

## 1. The formula

```
risk(test) =
    w_p  * priorityWeight(test)
  + w_a  * affectednessWeight(test)
  + w_f  * baselineFailWeight(test)
  + w_fl * flakeWeight(test)
  + w_ch * churnWeight(test)
  + w_r  * recencyWeight(test)
```

All components return values in `[0, 1]`. Weights are normalized so
`w_p + w_a + w_f + w_fl + w_ch + w_r == 1.0`. The output `risk` is
therefore also in `[0, 1]`, where 1.0 means "must run before
anything else" and 0.0 means "run only if budget permits".

Default weights (tuned on the TruthLayer pilot data):

| Component | Weight | Rationale |
|-----------|--------|-----------|
| `priorityWeight` (`w_p`) | **0.30** | P0 is load-bearing; missing a P0 is catastrophic |
| `affectednessWeight` (`w_a`) | **0.25** | The strongest structural signal — this test exercises code that just changed |
| `baselineFailWeight` (`w_f`) | **0.20** | Tests that have failed before regress again often |
| `flakeWeight` (`w_fl`) | **0.10** | Known flakes get extra attention but never dominate |
| `churnWeight` (`w_ch`) | **0.08** | A test file itself getting churned is a design-smell signal |
| `recencyWeight` (`w_r`) | **0.07** | Tests that haven't run in a while deserve a fresh look |

The weights are overridable via `test-strategy.md` →
`priorityEngine.weights`, but the override must:

- still normalize to 1.0 (±0.001) — the skill rejects an override
  whose sum diverges
- keep `w_p >= 0.2` — dropping priority below 20% is rejected as
  "override weakens the P0 signal"

---

## 2. Component definitions

### 2.1 `priorityWeight`

```
priorityWeight(test) = {
  P0 → 1.00
  P1 → 0.70
  P2 → 0.40
  P3 → 0.15
  unknown → 0.30 (with `degradedSignals: ["no priority tag"]`)
}
```

Priority comes from, in order of precedence:

1. The scenario id in the test file — if `scenario-set.md` names
   this test's scenario with an explicit `priority`, use it.
2. The test's tag — `@P0` / `@P1` / `@P2` / `@P3`. A test tagged
   multiple tiers falls back to the highest (P0 wins).
3. The test file's parent scenario — if the file has a
   `// @priority P0` header comment, inherit.
4. Baseline's `tests.<id>.priority` field.
5. Unknown → default 0.30 and degraded-signal note.

**A test tagged `@quarantined` is EXCLUDED from the candidate set
entirely**, not assigned priority 0. Quarantine is a human-level
decision; the risk model doesn't negotiate with it.

### 2.2 `affectednessWeight`

This is the structural signal that says "this test exercises code
that changed". It combines two sub-signals:

```
affectednessWeight(test) = clamp01(
    0.7 * directAffectedness(test)
  + 0.3 * transitiveAffectedness(test)
)
```

- **`directAffectedness`**: does the test file itself appear in the
  changed files list? That's 1.0. Otherwise 0.0.
- **`transitiveAffectedness`**: count the number of changed source
  files the test imports (transitively). Normalize by the total
  number of changed files. So a test that covers 3 out of 5
  changed files gets `3/5 = 0.6`.

When `codebase-intel` is unavailable, the skill falls back to
directory proximity: a test under the same directory subtree as
any changed file gets `transitiveAffectedness = 0.5`. This is
deliberate — the fallback is cheap and pessimistic, which is the
right direction.

### 2.3 `baselineFailWeight`

```
baselineFailWeight(test) = clamp01(
  baselineFailCount / 10
)
```

The `baselineFailCount` is the number of times this test has been
classified `new-failure` or `still-failing` in `regression-baseline.
json` history over the past 30 baseline promotions. A test that has
failed 5 times out of the last 30 runs scores 0.5. A test that has
never failed scores 0.

A cap of 10 is intentional: above 10, a test is probably broken
infrastructure, not a genuine risk signal. We want the plan to run
it, but not to let it dominate the ranking.

### 2.4 `flakeWeight`

```
flakeWeight(test) =
  flakyKnown[test]?.score ?? 0
```

Straight pass-through from `regression-baseline.json.flakyKnown` —
the score was already normalized to `[0, 1]` by
`ob_track_flaky`. P0 tests are never in `flakyKnown` (see
`regression-test-runner/references/baseline-policy.md`), so
`flakeWeight` only affects non-P0 tests in practice.

### 2.5 `churnWeight`

```
churnWeight(test) = clamp01(
  git_log_count_30d(test.file) / 30
)
```

The number of commits that touched the test file itself in the
last 30 days, normalized by 30. A test file touched once a day
scores 1.0; a cold test file scores ~0.0. High churn on a test
file usually correlates with the surrounding code being actively
developed, which is itself a risk signal.

When `git` is unavailable (disconnected environment), this
component returns 0 and the run records
`degradedSignals: ["no churn signal"]`.

### 2.6 `recencyWeight`

```
recencyWeight(test) = clamp01(
  daysSinceLastExecution / 14
)
```

The number of days since this test was last executed in a run that
made it into the baseline. Cap at 14. A test run every day scores
0; a test that hasn't run in 2 weeks scores 1.0.

The point is to surface tests that have been "asleep" and need a
fresh confidence check. A test that last ran a month ago is
effectively untested against the current state of the repo.

---

## 3. Tie-breakers

When two tests end up with identical risk scores (which happens
more often than you'd think with only 6 components and a lot of
P1s), the tie-breaker is:

1. Higher `priorityWeight` wins.
2. Lower baseline duration wins (faster tests run first in a tie).
3. Lexicographic test id — the last, completely deterministic
   break so the plan is byte-stable across runs.

---

## 4. What the risk model DOESN'T model

- **Semantic dependencies**. If test A depends on test B's side
  effect (a bad pattern, but real in legacy suites), the risk
  model doesn't know. The skill's output is a flat ordering; if
  an ordering dependency exists, `test-strategy.md` must declare
  it via `dependsOn` on the scenario.
- **Code coverage overlap**. Two tests that cover the same lines
  are treated as independent. Overlap-aware pruning is out of
  scope — it would need a coverage tool in the loop and the first
  version of this skill stays runner-agnostic.
- **Expected outcome**. We score likelihood of running a useful
  test, not likelihood of that test failing. The risk model is a
  historical + structural signal, not a failure oracle. Pretending
  otherwise would encode superstition as a weight.
- **Team ownership**. Who owns a test is an organizational signal,
  not a risk one. `learning-loop-engine` can reason about it
  later.

---

## 5. Component contribution transparency

Every row in the `priority-plan.md` table must show the risk score
AND the decomposition into components. Example:

```
| # | Test | Prio | Risk | Components                                                        |
|---|------|------|------|-------------------------------------------------------------------|
| 1 | ...  | P0   | 0.92 | p=0.30 a=0.25 f=0.18 fl=0.00 ch=0.12 r=0.07                       |
```

If a user complains "why is this test at position 3 instead of 1",
the decomposition is the audit trail. Never hide it.

---

## 6. Changing the weights

Not a silent edit — a weight change must:

1. Be accompanied by a retrospective on at least 20 historical
   runs showing the change improved failure capture without
   regressing false positives.
2. Bump the skill's internal `riskModelVersion` so downstream
   learning-loop tools can tell which plans were produced under
   which model.
3. Update this file AND the harness sentinel that asserts the
   current weight values.

Weight changes without all three are rejected at review time.
