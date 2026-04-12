# Baseline Policy

`regression-baseline.json` is the memory of the project's
verified-green state. Every rule in this file is a rule that keeps
that memory from lying. "Slow to update" is fine. "Quietly wrong"
is never fine.

---

## 1. File shape

`regression-baseline.json` lives at the repo root (or wherever
`test-strategy.md` declares via `baselinePath`). It is versioned
JSON; consumers read it; the skill is the only writer.

```json
{
  "schemaVersion": 1,
  "project": "<project name from vibeflow.config.json>",
  "lastPromotedAt": "2026-04-13T10:00:00Z",
  "promotedBy": "regression-test-runner@0.1.0",
  "runId": "20260413-100000-abc1234",
  "baseSha": "<git sha at promotion time>",
  "scope": "full",
  "totalTests": 842,
  "tests": {
    "<testId>": {
      "file": "tests/unit/auth.test.ts",
      "name": "login > rejects wrong password",
      "priority": "P0",
      "baselineStatus": "passed",
      "lastSeenAt": "2026-04-13T10:00:00Z",
      "durationMsBaseline": 17,
      "tags": ["@smoke", "@auth"]
    }
  },
  "quarantined": ["<testId>", "..."],
  "flakyKnown": {
    "<testId>": { "score": 0.23, "firstSeenAt": "2026-04-01T00:00:00Z" }
  }
}
```

Field rules:

- **schemaVersion** — bumped on any breaking change (add/remove
  fields, re-purpose semantics). Current version: **1**.
- **lastPromotedAt** — the time the baseline was last promoted by a
  verdict-`PASS` run. Used for the staleness check (§4).
- **baseSha** — the git SHA the promotion ran against. Downstream
  diff tools use this to reconstruct "what the world looked like at
  promotion".
- **scope** — the scope of the run that did the promotion. A `full`
  promotion is authoritative for every test; a `smoke` promotion
  only refreshes the smoke subset (see §3).
- **tests** — a map keyed by stable test id (`<file>::<name>`),
  matching the `NormalizedTest.id` from observability.
- **baselineStatus** — always `passed`, `failed`, or `skipped`. A
  `pending` status is never written to the baseline; pending is an
  in-flight state, not a historical state.
- **durationMsBaseline** — observed duration at promotion time.
  Consumed by `test-priority-engine` to rank tests and by
  `observability-analyzer` to establish a per-test baseline.
- **tags** — copied from the source file's tag scan so consumers
  don't re-scan.
- **quarantined** — tests the team has decided to ignore for now.
  They are NEVER promoted and NEVER gate. They exist in the baseline
  as a memory of "we know these are broken; leave them alone".
- **flakyKnown** — tests the historical cross-check classified as
  flaky. The gate does not shield P0 tests with this entry (see
  main SKILL §5); it's informational for non-P0 tests and used by
  `test-priority-engine`.

---

## 2. Promotion rules

A baseline is "promoted" when a run's verdict is `PASS` and the
skill writes a new `regression-baseline.json`. **No other verdict
promotes.** Not NEEDS_REVISION, not BLOCKED, not "mostly passing"
— only exact `PASS`.

### 2.1 What promotion does

1. Every test in the current run's `classified.json` whose
   classification is `still-passing`, `fixed`, or
   `new-test-passing` is written into `tests.<id>` with
   `baselineStatus: "passed"` and an updated `lastSeenAt`.
2. Every test classified `still-failing` is PRESERVED with its
   existing `baselineStatus: "failed"` and its original
   `lastSeenAt`. Promoting a `still-failing` test to `passed`
   would lose the "this test is stuck red" signal.
3. Every test classified `skipped` or `new-test-skipped` is
   written with `baselineStatus: "skipped"`.
4. Every test classified `not-executed` keeps its previous
   baseline entry untouched (see §3 on scope semantics).
5. `quarantined` entries are preserved exactly. Adding to or
   removing from this list is a manual edit — the skill will not
   change quarantine state.

### 2.2 What promotion does NOT do

- **Does not promote on a failing run.** The baseline stays
  pointing at the last PASS. The run's classified output is still
  written under `.vibeflow/artifacts/regression/<runId>/`, so
  downstream can inspect the failing run's details, but the
  baseline file itself is untouched.
- **Does not demote.** A passing test that was failing in the
  baseline is moved to `passed` (that's a "fix"). But a failing
  test that was passing in the baseline is NEVER written back to
  `passed` just because the run is friendly to it — that would
  require the run to also contain evidence the fail was real, not
  just a "the test got skipped this time".
- **Does not rewrite history.** The previous baseline is saved as
  `.vibeflow/artifacts/regression/baseline-history/<ISO>-<runId>.json`
  before the new one is written. Rollback is "copy the previous
  file back"; the skill never mutates a committed history file.
- **Does not delete tests.** A test that disappears from the
  current run (deleted from the suite) is PRESERVED in the
  baseline for one full `full` run cycle, then pruned on the
  following `full` promotion. Deleting immediately would lose the
  memory of what used to exist, which `learning-loop-engine`
  needs.

---

## 3. Scope semantics

The promotion is scoped to the run's scope. This is the subtle
rule that keeps fast smoke promotions from overwriting the slower
full baseline.

### `full` scope promotion
- Touches every `tests.<id>` entry — every test that ran gets
  `lastSeenAt` updated and every status is refreshed.
- Tests present in the previous baseline but `not-executed` in
  the current run (because the runner didn't discover them) are
  preserved with a WARNING in the run report: "full scope missed
  <id>, baseline entry frozen". This is almost always a runner
  misconfiguration.

### `smoke` scope promotion
- Touches ONLY the entries whose tests were in the smoke set.
  Non-smoke entries are preserved exactly.
- A smoke-scope PASS is still a PASS — the P0 gate is satisfied
  and no new failures were found. But the baseline's "last
  refresh" for non-smoke entries remains the last `full` run.
- Practical effect: the `lastPromotedAt` of a `smoke` run is
  recorded, but the staleness clock for non-smoke entries keeps
  advancing. Eventually the staleness guard (§4) trips and forces
  a `full` run.

### `incremental` scope promotion
- **Never promotes the baseline.** Even on PASS. An incremental
  run's affected set is too narrow to be a trustworthy snapshot;
  promoting it would silently validate parts of the suite the run
  didn't even look at.
- The run still records `classified.json` and the report, so the
  human gets the affected-set feedback. But the baseline stays
  frozen until a `smoke` or `full` run with verdict PASS visits
  it.

---

## 4. Staleness guard

The baseline has an expiration. If the last `full` promotion is
older than the staleness horizon, the skill refuses to compute a
gate verdict until a fresh `full` run is done.

### 4.1 Default horizons

| Scope of the pending run | Staleness horizon for the baseline |
|--------------------------|------------------------------------|
| `full` | 30 days — this run is the refresh, so "stale" here just bumps the horizon |
| `smoke` | 7 days since the last `full` promotion |
| `incremental` | 3 days since the last `full` promotion |

These are overridable in `test-strategy.md` via the
`baseline.staleness` block, but the override can only TIGHTEN the
horizons (fewer days). Loosening is forbidden — a config that
reads "incremental: 30 days" is rejected at load time as "config
weakens the staleness guard".

### 4.2 What happens when stale

1. The run still executes (we want to see what happened).
2. The verdict is computed as usual.
3. If the verdict would have been `PASS`, the skill downgrades it
   to `NEEDS_REVISION` with the specific reason `baseline stale
   beyond horizon`, and the baseline is NOT promoted.
4. The run report's "Next steps" section instructs the operator
   to run a `full` scope to refresh.

### 4.3 Cold start (no baseline)

- Only a `full` run can cold-start. A `smoke` or `incremental`
  run with no baseline blocks at the precondition stage with
  remediation "run a full scope first to establish a baseline".
- A cold-start `full` run records every test as `new-test-*` and
  promotes the baseline if P0 pass rate is 100%. The report
  banner flags it as a cold start so downstream analyzers know
  there's no "previous" to compare against.

---

## 5. Corruption + schema drift

- **Malformed JSON** → block the run at the precondition with
  "regression-baseline.json is malformed; restore from git or
  delete to cold-start".
- **Schema version mismatch** → block with "schema version <v>
  differs from <current>; run the migration tool" (the migration
  tool is out of scope for this skill, but the error message
  points at it).
- **Unknown fields** → ignored (forward compatibility), BUT
  logged to the run report so the operator knows the tool might
  be reading a newer file than it understands.
- **Missing required fields** → block with the specific missing
  field name.

---

## 6. Rollback

Rollback is always manual: the operator copies a previous
`baseline-history/<timestamp>-<runId>.json` back to
`regression-baseline.json` in git, commits, and re-runs. The skill
does not offer a `--rollback` flag because "which baseline to roll
back to" is a human decision.

The history files themselves are append-only. The skill writes
them; nothing else should overwrite them.

---

## 7. Interaction with `ob_track_flaky`

`regression-test-runner` Step 5 consults
`ob_track_flaky`, but the baseline's `flakyKnown` map is the
skill's own view, updated at promotion time:

- A test that was flagged `flaky` by the tracker in this run and
  is NOT P0 is recorded in `flakyKnown` with its current score.
- A test already in `flakyKnown` that comes back stable gets its
  entry removed — but only on a `full` scope promotion.
- **A P0 test is never added to `flakyKnown`.** P0 flakiness is a
  gate failure, not a known state. Writing a P0 into `flakyKnown`
  would feel like forgiveness, and forgiveness is
  `test-strategy.md`'s job (mark the test `@quarantined` or drop
  its P0 tag).

---

## 8. What this file does NOT cover

- The actual test runner invocation (Step 2 of the skill). Runner
  details live in the main SKILL.md.
- Scope selection (Step 1). See `scope-selection.md`.
- Per-test priority assignment. See `test-priority-engine` (S3-07).
- Cross-run flakiness scoring. See `observability/src/flakiness.ts`.

This file's single responsibility is "when and how does the
baseline change". Everything else is somebody else's problem.
