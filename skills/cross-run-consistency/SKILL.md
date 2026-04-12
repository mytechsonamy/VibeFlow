---
name: cross-run-consistency
description: Runs the same test N times in one session, diffs the outputs, and classifies non-determinism by root cause. Complements observability's historical flake tracking with an immediate "does this test agree with itself right now?" answer. Gate contract — P0 scenarios must be strict-consistent (same output on N/N runs), no tolerance fuzzing, no silent averaging. PIPELINE-5 step 3.
allowed-tools: Read Write Bash(npx *) Bash(npm *) Bash(git *) Grep Glob
context: fork
agent: Explore
---

# Cross-Run Consistency

An L2 Truth-Execution skill. It answers a specific question:
**"If I run this test right now, five times in a row, will the
five runs agree with each other?"**

That question is different from "has this test been flaky in the
past", which is what `observability` MCP's `ob_track_flaky` tool
answers. Historical flakiness looks backward across time, at
runs that were separated by code changes, environment drift,
and other noise. Cross-run consistency looks forward, in one
session, against an unchanged codebase — any disagreement is
pure non-determinism, because nothing else could have caused it.

Flaky tests that only show up historically usually hide behind
timing wobble; flaky tests that show up cross-run are faster to
diagnose because the search space is smaller.

## When You're Invoked

- **PIPELINE-5 step 3** — pre-release, after the regression
  suite has produced a clean baseline. A cross-run on the
  critical-path scenarios before shipping catches the last-
  mile non-determinism that a single green run can hide.
- **On demand** as
  `/vibeflow:cross-run-consistency <scenario-glob> [--runs N] [--mode strict|tolerant]`.
- **From `regression-test-runner`** when a test classified
  `flaky` in the baseline needs a fresh, session-local
  reproduction attempt before `release-decision-engine` uses
  it as a hard blocker.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Test scenario(s) | yes | Glob or explicit list. Matches the target's `scenario-set.md` ids, or direct file paths for runner-level tests. |
| Run count `N` | optional | Default: 5. Range: `[3, 50]`. A `--runs 1` is rejected — you can't check consistency with one observation. |
| Mode | optional | `strict` or `tolerant`. Default: `strict` for P0 tests, `tolerant` for everything else (the default honors the P0 rule). Explicit mode overrides only apply to non-P0 tests. |
| Tolerance declaration | optional | From `test-strategy.md → crossRunTolerance`. See `references/tolerance-modes.md` §2 for the shape. |
| `regression-baseline.json` | optional but preferred | Used to resolve test priorities (P0/P1/…) for the gate rule. |
| `observability` MCP | optional | When present, the skill reads historical flakiness to cross-reference findings — a test that's flaky historically AND cross-run is a stronger signal than either alone. |

**Hard preconditions** — refuse rather than emit a report the
user shouldn't trust:

1. The working tree must be clean (or `--allow-dirty` must be
   explicit). A dirty tree mixes "changes the user hasn't
   committed" with "non-determinism in the committed code" in
   a way the report cannot disentangle.
2. The test runner must be installed. Same rule as every
   runner-driven skill in Sprint 3.
3. `--runs` must be ≥ 3. Two runs disagreeing tells you
   something is non-deterministic but gives you no signal about
   whether it's rare or common; three is the minimum useful
   sample.
4. The scenario glob must resolve to at least one test.
   `0 scenarios` blocks — silently running nothing is how a
   session produces "100% consistent" with no real meaning.

## Algorithm

### Step 1 — Resolve mode per test
The mode is resolved per TEST, not per run. The skill walks the
scenario set:

- **P0 tests → `strict` always.** No override flag, no
  `--mode tolerant` escape. P0 tests must agree on every byte of
  output across every run; tolerance is a budget for places
  where you're willing to accept inexactness, and P0 is where
  you aren't.
- **Non-P0 tests → the default mode OR the explicit
  `--mode <value>` override OR the per-test mode declared in
  `test-strategy.md`.** Per-test overrides win over `--mode`,
  which wins over the default.

Record each test's resolved mode in the run metadata — the
report needs to show which mode each row was evaluated under.

### Step 2 — Capture the first run as baseline
Run the test once, record its output fully:

- Exit code
- stdout (full, not truncated — tests that dump megabytes of
  output aren't in the cross-run suite to begin with)
- stderr (full)
- Per-test duration
- Any file artifacts the test declares under
  `testArtifactPaths` in its config (screenshots, coverage,
  generated fixtures)

The first run is the baseline; subsequent runs diff against it.
The baseline is NOT allowed to be the "best" run — we don't
retry the baseline capture on failure. If the first run fails,
the report records "baseline failed" and the skill moves on to
the next test (no point running a non-deterministic check
against a baseline that doesn't exist).

### Step 3 — Run the remaining N-1 executions
Run sequentially, never parallel. Parallel execution introduces
a confound (shared state via parallel workers, file handle
races, port collisions) that would make the consistency signal
meaningless. Cross-run runs are slow on purpose.

For each execution:

1. Clear the test's declared `testArtifactPaths` between runs
   (stale screenshots from run 2 would look like non-determinism
   in run 3).
2. Reset any ephemeral environment state the scenario declares
   (`envReset` commands from `test-strategy.md`).
3. Run the test with the same runner + same seed + same
   fixture data as run 1.
4. Capture the same fields as the baseline.

### Step 4 — Diff against the baseline
For each subsequent run's output, diff against the baseline
according to the test's resolved mode:

- **`strict`** — byte-for-byte. Exit code, stdout, stderr, per-file
  artifacts all must be byte-identical.
- **`tolerant`** — within the declared tolerances for that type
  of output. See `references/tolerance-modes.md` §3.

Any diff that exceeds the mode's allowance is recorded as an
inconsistency finding. A single inconsistency is enough to
drop the per-test consistency score below 1.0 — see Step 6.

### Step 5 — Classify every inconsistency
For each finding, walk `references/non-determinism-taxonomy.md`
and pick the first matching class:

1. `TIMING` — output depends on wall-clock time, scheduling,
   or `Date.now()` / `performance.now()` leaking into the
   output
2. `ORDERING` — sets / maps / file-system reads that don't
   guarantee order
3. `SEED-DRIFT` — PRNG state differs between runs (usually a
   missed seed pin)
4. `EXTERNAL-STATE` — the test reads from something outside
   its own process (network, shared cache, real clock)
5. `RESOURCE-CONTENTION` — CPU or memory pressure from
   other workloads changes the test's behaviour
6. `UNKNOWN` — none of the above match. UNKNOWN findings are
   recorded but flagged for human triage, not silently
   bucketed.

The skill NEVER invents a new class at prompt time. If a real
finding consistently classifies as UNKNOWN, the fix is to add a
new class to the taxonomy with a retrospective, not to let the
skill "figure it out".

Every classification cites both the taxonomy class id AND a
confidence score `[0,1]`. Low-confidence classifications
(<0.6) are surfaced in the report as "probable <class>" and
flagged for human review.

### Step 6 — Compute the consistency score
Per test:

```
perTestConsistency =
  (runs that matched the baseline within the test's mode)
  / (total runs — 1)    // exclude the baseline run itself
```

Range: `[0, 1]`. A test that agreed with its baseline on every
subsequent run scores 1.0. A test that disagreed every time
scores 0.0.

Overall run:

```
overallConsistency = (# tests with perTestConsistency == 1.0) / (# tests)
```

We deliberately don't average the per-test scores — "9 out of
10 tests fully agreed and 1 was 50% consistent" means 9/10, not
9.5/10. A partially-consistent test is as dangerous as a fully-
inconsistent one from a release-gate standpoint.

### Step 7 — Apply the gate
**Gate contract: P0 scenarios must be strict-consistent — same
output on N out of N runs. Non-P0 scenarios must meet the
overall consistency threshold for the domain.**

Verdict:

| Condition | Verdict |
|-----------|---------|
| Every P0 scored 1.0 in strict mode AND overall ≥ threshold | PASS |
| Every P0 scored 1.0 AND overall < threshold | NEEDS_REVISION |
| Any P0 scored < 1.0 | BLOCKED |

Domain thresholds (see `references/tolerance-modes.md` §4 for
the rationale):

| Domain | Non-P0 overall threshold |
|--------|--------------------------|
| `financial` | 0.98 |
| `healthcare` | 0.98 |
| `e-commerce` | 0.93 |
| `general` | 0.90 |

No override flag on the P0 strict rule. A P0 that's
inconsistent at the current commit is a release-blocker —
either fix the test, pin the seed, remove the time dependency,
OR drop the test's P0 tag in `test-strategy.md` (which is a
human decision, not a skill decision).

### Step 8 — Write outputs

1. **`.vibeflow/reports/consistency-report.md`** — human-
   readable report with per-test rows, classified findings,
   confidence scores, and probable-cause hints
2. **`.vibeflow/artifacts/consistency/<runId>/per-run/<i>.json`**
   — one file per execution, so the raw inputs to the diff are
   archived for post-mortem
3. **`.vibeflow/artifacts/consistency/<runId>/diffs.jsonl`** —
   one JSON object per inconsistency finding (append-only,
   crash-safe)

## Output Contract

### `consistency-report.md`
```markdown
# Cross-Run Consistency Report — <runId>

## Header
- Run id: <runId>
- Runs per test: 5
- Mode defaults: strict (P0) / tolerant (non-P0)
- Tests executed: T
- Overall consistency: X.XX (vs threshold Y.YY)
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Summary
- P0 tests: p (all must score 1.0 — see §Critical inconsistencies)
- Fully consistent tests (score 1.0): a
- Partially consistent tests: b
- Fully inconsistent tests: c
- Baseline failures: d

## Critical inconsistencies (gate-blocking)
### <testId>
- Priority: P0
- Mode: strict
- Per-test consistency: 0.40 (2/5 runs agreed)
- Probable cause: TIMING (confidence 0.82)
- Evidence: stdout differs on lines 12, 37 — timestamps present
- Suggestion: pin Date.now() to a fake clock or remove timestamp from the assertion

## Non-critical inconsistencies
### <testId>
- Priority: P2
- Mode: tolerant (pixel tolerance 0.05)
- Per-test consistency: 0.60 (3/5 runs agreed)
- Probable cause: EXTERNAL-STATE (confidence 0.55) — "probable"
- Evidence: <brief evidence>

## Classification breakdown
| Class | Count |
|-------|-------|
| TIMING | x |
| ORDERING | y |
| SEED-DRIFT | z |
| EXTERNAL-STATE | w |
| RESOURCE-CONTENTION | v |
| UNKNOWN | u |

## Baseline failures
- <testId>: baseline run returned exit code 1
  - Tests with a failing baseline are NOT scored for consistency
  - `regression-test-runner` should have caught this first
```

## Gate Contract
**P0 scenarios must be strict-consistent — same output on every
run.** The three invariants:

1. P0 tests ALWAYS evaluate in `strict` mode regardless of
   `--mode` or `test-strategy.md` overrides. No flag opens this.
2. A P0 test that scores < 1.0 is BLOCKED regardless of the
   overall aggregate. Partial consistency on a P0 is the same
   quality signal as a fully inconsistent P0 — both say "I
   can't tell you what this test will do next time".
3. Non-P0 tests follow the domain threshold, BUT a fully
   inconsistent non-P0 test (score 0.0) is always at least
   NEEDS_REVISION even if the aggregate meets the threshold.
   Burying a silently-broken test under aggregate math is
   exactly what this skill exists to prevent.

## Non-Goals
- Does NOT replace `ob_track_flaky`. Historical flakiness is a
  different signal; cross-run-consistency is the session-local
  complement.
- Does NOT fix non-determinism. It classifies and points at it.
  The fix is human.
- Does NOT run in CI by default. Cross-run is slow (N× the test
  cost); it runs on release-track pipelines, not every PR.
- Does NOT average per-test scores. Averaging hides partially-
  consistent tests in a "mostly good" aggregate — see Step 6.
- Does NOT retry a failed baseline. If run 1 fails, the test
  has a bigger problem than consistency.

## Downstream Dependencies
- `release-decision-engine` — reads the P0 strict-consistency
  count as a hard blocker; the overall consistency score feeds
  the weighted quality score
- `observability-analyzer` — cross-references cross-run
  findings with historical `ob_track_flaky` data to spot
  "test that's been failing historically AND is non-deterministic
  right now" (a stronger signal than either alone)
- `learning-loop-engine` — ingests classification history to
  spot systematic root causes across the codebase
