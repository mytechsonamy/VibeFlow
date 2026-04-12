# Mode Budgets

The skill's three modes + their default budgets + the rules for
tightening them safely. A mode is a target time window; the risk
model picks which tests to fit into it.

---

## 1. The three modes

### `quick`

- **Intent**: the PR author's first feedback signal. "Did I
  break anything obvious?"
- **Default time budget**: 60 seconds (wall clock, not sum of
  durations — parallelism is the runner's job)
- **Default count budget**: 40 tests
- **Mandatory inclusions**: every **affected** P0 test, regardless
  of whether they fit. Budget overflow on the P0 set emits
  `budgetExceeded: true, reason: "P0 mandatory set"` in the
  report.
- **Typical caller**: `regression-test-runner` on a PR trigger,
  pre-commit hook that wants sub-minute feedback
- **NOT for**: releases, nightly runs, exhaustive coverage

### `smart`

- **Intent**: the "I have a few minutes to think about this" mode.
  Balances affected-set coverage with risk-weighted sweep.
- **Default time budget**: 10 minutes
- **Default count budget**: 300 tests
- **Mandatory inclusions**: every affected P0, every non-affected
  P0 that has failed in the last 5 baseline promotions, every
  known flake with priority ≥ P1
- **Typical caller**: pre-merge CI stage, release rehearsal
- **Good for**: most manual `/vibeflow:test-priority-engine` runs

### `full`

- **Intent**: exhaustive coverage. Priority here is about
  **ordering** — the runner is going to execute everything anyway,
  but the plan determines which tests run first and therefore
  which failure you see first.
- **Default time budget**: unbounded (effectively the runner's
  own timeout)
- **Default count budget**: unbounded
- **Mandatory inclusions**: every P0 test, affected or not, with
  priority-weight tiebreakers
- **Typical caller**: PIPELINE-5 pre-release run, scheduled nightly
- **Special behavior**: the plan's `spill` list is always empty
  (nothing is over budget), but the top-K section still captures
  "these are the first tests I'd run if I had to stop early"

---

## 2. Budget interaction rules

- **Overrides may only TIGHTEN the defaults.** `--time-budget 30`
  on `quick` is fine; `--time-budget 300` on `quick` is rejected
  as "override widens the mode; use `smart` instead". The same
  applies to `--count-budget`.
- **The two budgets are independent AND-ed**. A plan is over
  budget when EITHER the time cumulative exceeds the time budget
  OR the count exceeds the count budget. This keeps "one slow
  test" from eating the whole wall-clock budget and also keeps
  "300 micro-tests" from flooding a short window.
- **Overflow order of penalties**: when the plan fills up, tests
  are removed from the tail (lowest risk) until the plan fits. P0
  mandatory inclusions are NEVER removed — they overflow the
  budget and the report records it.
- **Negative budgets are rejected.** `--time-budget 0` or
  `--count-budget 0` are rejected as "budget must be positive".
- **The 10-second floor**. `--time-budget 5` is rejected as "too
  short to produce a useful plan". The floor protects users from
  footguns.

---

## 3. Duration estimation

Time budgeting requires knowing how long each test takes. Sources,
in order of preference:

1. **Baseline duration** — `regression-baseline.json.tests.<id>.durationMsBaseline`.
   Set during `regression-test-runner`'s PASS promotions. Most
   reliable.
2. **Observability history** — `ob_perf_trend`'s rolling average
   duration per test. Second best; includes trend information.
3. **Tag-based defaults** — `@slow` = 30s estimate, `@fast` = 0.5s,
   untagged = 2s. Coarse, but good enough when other signals are
   cold.
4. **Count-budget fallback** — when no duration estimate exists for
   any test, the skill falls back to count-only packing. The
   report records `budgetMode: "count-only"` so consumers know.

Duration estimates are always recorded per test in the plan's
output, with the source noted — operators can audit "why did you
think this test was 2 seconds when it took 40".

---

## 4. Cold-start + degraded-signal fallbacks

A mode is still useful even when inputs are incomplete. The skill
falls back gracefully but NEVER silently:

### No baseline
- `priorityWeight` and `affectednessWeight` still work — they
  read from git + scenario-set.
- `baselineFailWeight` returns 0 for every test (no history).
- `recencyWeight` returns 1.0 for every test (everything is
  "stale" if there's no record of ever running it).
- Report header: `degradedSignals: ["no baseline"]`.
- The skill DOES still emit a plan, tagged `coldStart: true`.
- `regression-test-runner` calling in cold-start mode must use
  `full` scope — see that skill's baseline-policy §4.3.

### No scenario-set
- `priorityWeight` falls back to tag-based / header-based priority
  detection. P0 is still detected via `@P0` tag.
- Risk components unaffected otherwise.
- Report header: `degradedSignals: ["no scenario-set"]`.

### No codebase-intel
- `affectednessWeight` falls back to directory proximity (§2.2 in
  `risk-model.md`).
- Report header: `degradedSignals: ["codebase-intel unavailable"]`.
- Affected-set calculation is still deterministic — just wider.

### No flakiness history
- `flakeWeight` returns 0 for every test.
- Report header: `degradedSignals: ["no flakiness history"]`.
- The skill still emits a plan — flake weight is 10% of the total,
  so losing it is graceful.

### All inputs cold (worst case)
- Skill refuses to run. See SKILL.md §Preconditions — the floor
  is "at least ONE priority signal must exist". An empty context
  cannot produce a trustworthy plan and silently emitting one
  would teach humans to trust garbage.

---

## 5. Mode-specific P0 rules

**Every mode treats P0 differently in the non-affected set**:

| Mode | Affected P0 | Non-affected P0 |
|------|-------------|-----------------|
| `quick` | Mandatory | Omitted (quick is affected-only by design) |
| `smart` | Mandatory | Included if they failed in last 5 baseline promotions |
| `full` | Mandatory | All included |

The affected P0 inclusion is non-negotiable in every mode. The
non-affected P0 handling is the only thing that actually changes.

---

## 6. What modes do NOT do

- **Do not try to predict runtime under parallelism.** The time
  budget is a wall-clock target, not a computation of "sum /
  cores". Runners with good parallelism will finish faster; the
  budget just prevents the plan from shipping 3 hours of tests
  into a 5-minute window.
- **Do not inherit mode from the previous run.** Every invocation
  resolves mode from the current flags, not from history. Leaking
  mode across runs is how "oh it was smart last time" bugs creep
  in.
- **Do not silently promote or demote modes.** If a `quick` mode
  can't fit the P0 mandatory set, it reports overflow — it does
  NOT auto-promote to `smart`. The operator decides.

---

## 7. Mode versioning

Each mode definition is versioned alongside the skill. Breaking
changes to the default budgets or the mandatory-inclusion rules
bump the mode config version, which is recorded in the plan
header. Consumers (like `learning-loop-engine`) use the version
to bucket historical plans correctly.

Current mode config version: **1**.

Mode version bumps follow the same discipline as the risk model:
retrospective on ≥20 runs + update this file + update the harness
sentinel. Silent edits are rejected at review time.
