# Resilience Scoring Rubric

How `chaos-injector` turns a sequence of injection outcomes into
a resilience score, and where the per-profile thresholds live.
This file is the single source of truth for both questions.
Changing a threshold or a weight is a governance move, not a
config tweak — same discipline as `mutation-test-runner`'s score
thresholds.

---

## 1. Profile thresholds + allow-lists

| Profile | Resilience score threshold | Chaos types allowed |
|---------|----------------------------|---------------------|
| `gentle` | **85 / 100** | `net-latency-low`, `net-drop-small`, `dep-slow` (2s variant) |
| `moderate` | **70 / 100** | Everything in `gentle` + `net-latency-high`, `net-drop-large`, `dep-stop`, `dep-slow` (aggressive variant), `clock-skew-future`, `clock-skew-past` |
| `brutal` | **55 / 100** | Everything in `moderate` + `cpu-stress`, `memory-stress`, `disk-fill`. Cascading failures are **allowed** at brutal (the whole point is to find where they cascade). |

**Why the gap is so wide between profiles:**

- `gentle` gets the highest bar because the whole point of
  gentle chaos is "the baseline case — every system should
  survive this without degrading noticeably". Missing the
  gentle threshold is a sign something is fundamentally wrong
  with the system's failure assumptions.
- `brutal` gets the lowest bar because brutal runs are
  expected to find real weaknesses. Scoring too high on brutal
  means the chaos wasn't harsh enough.

**Cascading-failure rule on `gentle`:** independent of the
score, any cascading failure at gentle intensity is an
automatic BLOCKED. Even if the score would be 95/100 with a
cascade, the cascade alone ships BLOCKED.

---

## 2. Resilience score formula

The score is a weighted sum of four components, each in `[0, 1]`.
Weights sum to 1.0; the final score is the weighted sum times 100
so the output is in `[0, 100]`.

```
score =
    w_r  * recoveryComponent
  + w_b  * blastRadiusComponent
  + w_e  * expectationComponent
  + w_h  * persistentHealthComponent
```

Default weights:

| Component | Weight | Rationale |
|-----------|--------|-----------|
| `recoveryComponent` (`w_r`) | **0.35** | "Did it recover?" is the single most important signal — a system that doesn't recover from tame chaos is broken at rest |
| `blastRadiusComponent` (`w_b`) | **0.30** | Blast radius tells you whether failures are containable, which is the whole architectural promise of decomposition |
| `expectationComponent` (`w_e`) | **0.20** | Did the observed degradation match what the scenario predicted? An unpredictable system is worse than a broken one — you can't build confidence on it |
| `persistentHealthComponent` (`w_h`) | **0.15** | Even after recovery, did components return to their baseline state or carry damage forward? |

Weight overrides are allowed via `test-strategy.md →
chaosInjector.weights`, subject to the same disciplines as the
mutation score thresholds:

- Weights must renormalize to 1.0 (±0.001)
- `w_r >= 0.25` floor — "did it recover" always dominates
- Override requires a retrospective on ≥10 historical chaos runs
  showing the change captures a real weakness the default missed
- The override is version-bumped in `chaosConfigVersion` and
  recorded in every report

---

## 3. Component definitions

### 3.1 `recoveryComponent`

```
recoveryComponent =
  (# injections that verified recovery within the abort window)
  / (# injections attempted)
```

- **verified recovery** means the recovery command ran AND the
  post-injection healthcheck passed within
  `maxBlastRadiusSeconds` (catalog field per chaos type)
- an injection that was aborted for blast-radius overflow counts
  as an UNrecovered injection (the recovery never had a chance
  to run cleanly)
- an injection where the catalog's recovery command itself threw
  a runtime error counts as unrecovered

**Minimum one attempted injection per run.** A run with zero
injections fails preflight — there's nothing to score.

### 3.2 `blastRadiusComponent`

```
blastRadiusComponent = 1 - (blastOverflowCount / attemptedInjections)
```

- **blastOverflowCount** = the number of injections where a
  component outside the target's declared `dependsOn` chain
  became unhealthy during the injection, OR where the observed
  error rate on unrelated paths exceeded the profile's allowed
  threshold.
- A run with every injection contained scores 1.0 on this
  component.
- A run where every injection leaked scores 0.0.

### 3.3 `expectationComponent`

```
expectationComponent =
  (# injections where observed degradation matched expectedDegradation)
  / (# injections attempted)
```

- `expectedDegradation` comes from the scenario's declaration —
  a plain-text description the skill matches against the
  observed metric dip using a loose threshold rule (observed
  metric value within ±50% of expected). A tighter match is
  nice to have but rarely achievable in real runs; the 50%
  band is the honest band.
- A scenario with no `expectedDegradation` field defaults to
  "system should keep working" — i.e. NO significant
  degradation, and any degradation counts as a mismatch.

### 3.4 `persistentHealthComponent`

```
persistentHealthComponent =
  (# components healthy in final-state.json at the baseline level)
  / (# components in the system)
```

- **baseline level** means the same health status AND within
  ±20% of the preflight latency baseline. A component that
  returned to healthy but now has 3x the latency isn't fully
  recovered — this component catches that.
- A component that stayed broken after the run (`finalState.unhealthy`)
  counts as 0 contribution to the numerator.

---

## 4. Aborts and their scoring consequence

Aborts are the skill's safety net. They stop a run when
something is going wrong faster than the observer can keep up.
Scoring rules:

- **recovery-failure abort** → `recoveryComponent` gets a 0
  contribution for the aborted injection, AND the whole run's
  verdict becomes BLOCKED regardless of the computed score.
  The score is still written to the report for the record, but
  the verdict is hard-coded by the abort.
- **blast-radius abort** → same as recovery-failure: the score
  is informational, the verdict is BLOCKED.
- **preflight abort** → no injections ran; the run is BLOCKED
  and the report says so. No score is written because there's
  nothing to score.

**No abort weights the score down in a "partial credit" way.**
An abort is a structural failure, not a points loss. Giving
partial credit for an abort is how aborts silently become
accepted.

---

## 5. The cascading-failure rule (gentle profile only)

At `gentle` intensity, ANY of the following conditions sets the
verdict to BLOCKED regardless of the overall score:

- More than ONE component becomes unhealthy during a single
  injection. (Gentle chaos should affect exactly the target and
  its direct synchronous dependents, and those should degrade
  gracefully, not fail.)
- Two or more injections in a row show blast-radius overflow on
  the SAME unrelated component. (A single slip could be noise;
  two in a row on the same target is a fragility signal.)
- The run's observed error rate doubles compared to preflight
  baseline and doesn't recover within 30 seconds of the
  recovery command running. (Fragile recovery is not recovery.)

None of these rules applies to `moderate` or `brutal` — finding
cascading failures IS the point at those intensities. The rule
is structural to `gentle`: gentle chaos that cascades means the
system is broken before you've even started the real test.

---

## 6. Changing the thresholds or weights

Same discipline as `mutation-test-runner`'s thresholds:

1. Retrospective on ≥10 historical chaos runs showing the
   change improves signal without losing safety
2. `chaosConfigVersion` bump (every report records the version
   so downstream consumers can bucket historical scores)
3. Migration note in the PR
4. Integration harness sentinel update (see §8 in the harness
   rules — the current values are asserted so silent edits fail
   CI)

Silent edits to this file land as a CI failure, not a merge.
Chaos thresholds are easier to change than chaos incidents are
to apologize for.

---

## 7. Current config version

**`chaosConfigVersion: 1`**

- Profile thresholds: `gentle: 85 / moderate: 70 / brutal: 55`
- Weight defaults: `w_r: 0.35, w_b: 0.30, w_e: 0.20, w_h: 0.15`
- Weight floor: `w_r >= 0.25`
- Score range: `[0, 100]` with integer rounding in the report

Every chaos report writes the version in its header so
historical reports stay interpretable even after a version bump.
