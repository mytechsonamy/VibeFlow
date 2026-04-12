---
name: mutation-test-runner
description: Generates code mutations from a fixed operator catalog, runs the test suite against each mutant, and computes the mutation score. A surviving mutant points directly at an assertion that doesn't actually check what it claims. Gate contract — zero surviving mutants in P0 code + domain-specific mutation score threshold. PIPELINE-2 step 2 (conditional) / PIPELINE-6 step 2.
allowed-tools: Read Write Bash(npx *) Bash(node *) Bash(git *) Grep Glob
context: fork
agent: Explore
---

# Mutation Test Runner

An L2 Truth-Execution skill. Line coverage tells you which code was
executed; mutation testing tells you which assertions were
**verifying** the execution. A test that runs a function without
asserting on its output has 100% line coverage and 0% mutation
score — the two metrics disagree precisely where regressions slip
through. This skill measures the gap.

Where `regression-test-runner` tells you "did the tests pass",
mutation-test-runner tells you "did the tests actually test". That
second question is the one `release-decision-engine` leans on for
quality signals beyond raw coverage.

## When You're Invoked

- **PIPELINE-2 step 2 (conditional)** — run when the PR diff touches
  domain-critical code (financial ledger, auth path, healthcare PHI
  handler). The condition is set by the domain's
  `criticalPaths` list in `vibeflow.config.json`. Non-critical PRs
  skip mutation testing at this stage — it's too slow for every
  commit.
- **PIPELINE-6 step 2** — every pre-release run, full scope. This is
  where the mutation score feeds the release decision.
- **On demand** as `/vibeflow:mutation-test-runner [--files <glob>] [--scope <s>]`.
- **From `release-decision-engine`** when the decision engine needs
  a fresh mutation signal for the GO/CONDITIONAL call.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Source files | yes | Glob or explicit list. Default: all tracked source files. |
| Test files | yes | Derived from `repo-fingerprint.json` or globbed by convention. A run with no tests blocks — mutating code with no tests is a "what were you expecting" situation. |
| `mutation-baseline.json` | optional | Previous baseline for diff reporting (new survivors vs ones that were already there). Absent → cold-start mode, first survivor wave is informational. |
| `regression-baseline.json` | optional but preferred | Supplies the priority tags (P0/P1/…) that feed the P0 zero-survivor rule. |
| Domain config | yes | `vibeflow.config.json` → `domain`. Drives which threshold from `score-thresholds.md` applies. |
| `--scope` | optional | `full` / `affected`. Default: `affected` for PR trigger, `full` for release trigger. |
| `--operators` | optional | Subset of operator ids from the catalog. Default: the full `default` set. |
| Runner availability | derived | `stryker` (or any mutation runner that supports JSON output) via `repo-fingerprint.json`. Unknown runner blocks. |

**Hard preconditions** — refuse to run rather than emit a score
nobody should trust:

1. `regression-test-runner` must have produced a PASS verdict on
   the current HEAD (or the `--allow-unverified` flag must be
   explicit). A run against a broken test suite produces a
   garbage score — every mutant "survives" because every test
   was already failing.
2. The mutation runner must be installed. Missing runner blocks
   with remediation "install stryker (or equivalent) before
   re-running".
3. The scope must resolve to at least one source file. Empty
   scope blocks — "mutate nothing" is not a useful run.
4. P0 code paths (from `regression-baseline.json.tests[*].priority`)
   must have tests. A P0 file with no corresponding test file
   blocks with "no test file for <P0 source>: mutation testing
   cannot score untested code".

## Algorithm

### Step 1 — Resolve scope + operators
Scope rules:

- **`affected`** — source files changed since the last PASS
  baseline (from git diff + `ci_dependency_graph`). Matches the
  scope pattern from `test-priority-engine`.
- **`full`** — every source file under the project's
  `sourceDir` from `vibeflow.config.json`, minus any path matching
  `mutationIgnore` in `test-strategy.md` (generated code,
  third-party vendored files, translation bundles).

Operators: the default set from
`references/mutation-operators.md` is applied unless the user
passes `--operators <id,id,...>`. An unknown operator id blocks —
silently ignoring is how a user ends up with a report that says
"100% mutation score" because all the interesting operators got
typo'd out.

### Step 2 — Generate mutants
For each source file in scope, apply every selected operator to
produce a list of `Mutant` records:

```ts
interface Mutant {
  id: string;                 // "<file>::<operator>::<location>"
  file: string;
  operatorId: string;
  originalSnippet: string;
  mutantSnippet: string;
  line: number;
  column: number;
  priority: "P0" | "P1" | "P2" | "P3"; // inherited from the enclosing test's priority
  equivalentFilterResult: "run" | "skip-equivalent";
}
```

The `equivalentFilterResult` is set by the equivalent-mutant
filters in `mutation-operators.md` §4. A mutant flagged
`skip-equivalent` is recorded in the report but NOT sent to the
runner — we don't waste time on mutants that the catalog has
pre-identified as semantically identical to the original.

### Step 3 — Dispatch the runner
Hand the mutant list to the configured mutation runner. Stryker
is the default for TS/JS; other runners (Mutmut for Python,
Pitest for Java) are supported through the same `MutationRunner`
abstraction — the skill only cares that the runner accepts a
mutant list and returns a per-mutant outcome.

Runner outcome per mutant:

- **killed** — at least one test failed when run against the
  mutant
- **survived** — every test passed against the mutant (the
  mutation slipped through)
- **timeout** — the runner hit the per-mutant timeout (see §3.1)
- **runtime-error** — the mutant caused a syntax or type error
  that the runner couldn't even execute
- **no-coverage** — no test file touches this line, so no test
  was run against it

`timeout` classifies as `killed` by default (the test hit a
pathological case and aborted — the mutant changed observable
behavior enough to matter), but the report flags it separately so
operators can audit the timeout count.

`runtime-error` classifies as `killed` (the mutant broke
compilation; the test harness saw the break) but flagged
separately — a large runtime-error count usually means the
catalog's equivalent-mutant filter needs tightening.

`no-coverage` classifies as `survived` AND is flagged as the
strongest "weak assertion" signal in the report: you literally
have a line of code that no test touches.

### Step 4 — Compute the mutation score
```
total       = mutants.length
skipped     = mutants.filter(equivalentFilterResult == "skip-equivalent").length
executed    = total - skipped
killed      = mutants.filter(outcome == "killed").length
              // includes timeouts + runtime-errors
survived    = mutants.filter(outcome == "survived").length
noCoverage  = mutants.filter(outcome == "no-coverage").length

mutationScore = executed > 0 ? killed / executed : 0
```

The `noCoverage` count is NOT subtracted from the denominator —
it's counted as survived. The reason: excluding no-coverage
mutants would let a repo with 20% line coverage score a clean
100% on a tiny executed set. The definition of "quality" we care
about includes "did you even write the test".

### Step 5 — Apply the gate

The gate has TWO rules, both of which must pass:

1. **P0 zero-survivor rule**: every mutant in P0 code (where
   priority is inherited from the test file that would exercise
   it) must be either `killed`, `skip-equivalent`, or
   `runtime-error`. A P0 `survived` mutant blocks, full stop.
2. **Mutation score threshold**: `mutationScore >= threshold(domain)`,
   where `threshold` comes from `references/score-thresholds.md`.
   Financial / healthcare domains have higher thresholds than
   general.

Verdict:

| Condition | Verdict |
|-----------|---------|
| `p0Survivors == 0 && mutationScore >= threshold` | PASS |
| `p0Survivors == 0 && mutationScore < threshold && mutationScore >= (threshold - 0.05)` | NEEDS_REVISION — close to the bar |
| `p0Survivors == 0 && mutationScore < (threshold - 0.05)` | BLOCKED — score is meaningfully under |
| `p0Survivors > 0` (any priority of the SOURCE path) | BLOCKED — survivors in P0 code are non-negotiable |

**Gate contract: zero surviving mutants in P0 code, and the
mutation score must meet the domain threshold.** Not "mostly
meet" — meet. The NEEDS_REVISION band exists for close misses so
the author can still land with a scheduled fix, but a score
far below the threshold fails outright.

### Step 6 — Identify weak assertions
For every survived mutant, the report includes a "probable weak
assertion" line: the test file that should have caught it, the
line the mutant lives on, and the specific operator that slipped
through. Example:

> Mutant `src/pricing.ts:42::CONDITIONAL_BOUNDARY` survived.
> The test at `tests/unit/pricing.test.ts:17` exercised this
> line but the assertion `expect(result).toBeTruthy()` doesn't
> distinguish the boundary. Tighten the assertion to check the
> specific expected value.

The skill doesn't rewrite the test — it points at the weakness.
`component-test-writer` might later generate a stricter test, but
that's a downstream concern.

### Step 7 — Write outputs

1. **`.vibeflow/reports/mutation-report.md`** — human-readable
   report (see contract below)
2. **`.vibeflow/artifacts/mutation/<runId>/mutants.json`** —
   per-mutant details, stable for `learning-loop-engine` consumption
3. **`mutation-baseline.json`** — updated ONLY when verdict is
   `PASS`, same discipline as `regression-baseline.json`. Append
   history to `.vibeflow/artifacts/mutation/baseline-history/`.
4. **`.vibeflow/reports/weak-assertions.md`** — a focused list of
   "these tests need tightening" that `component-test-writer` and
   humans can act on.

## Output Contract

### `mutation-report.md`
```markdown
# Mutation Report — <runId>

## Header
- Run id: <runId>
- Scope: full | affected
- Domain: financial
- Threshold: 0.80 (financial)
- Mutation runner: stryker@x.y.z
- Source files mutated: N
- Started: <ISO>
- Duration: <ms>
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Summary
- Total mutants: T
- Skipped (equivalent filter): S
- Executed: E
- Killed: K (including Ktimeout=ko, Kerror=ke)
- Survived: V
- No coverage: C (counted as survived)
- **Mutation score: XX.X%** (vs threshold 80.0%)
- **P0 survivors: 0** (gate-blocking if > 0)

## Critical survivors (gate-blocking)
### <mutant id>
- File: src/pricing.ts:42
- Operator: CONDITIONAL_BOUNDARY
- Priority: P0
- Probable weak test: tests/unit/pricing.test.ts:17
- Original: `if (amount > 100)`
- Mutant: `if (amount >= 100)`
- Suggestion: assertion on line 17 uses toBeTruthy; change to toEqual(expected)

## Non-critical survivors
<same shape, lower priority>

## No-coverage mutants
<list — these are lines no test touches; fix coverage first>

## Timeout + runtime-error summary
- Timeouts: <count> (classified as killed)
- Runtime errors: <count> (classified as killed)
- Large counts here suggest the equivalent-mutant filter needs work
```

### `weak-assertions.md`
```markdown
# Weak Assertions — <runId>

## Summary
- Weak assertion candidates: N
- P0 weak assertions: a (gate-blocking)
- Files affected: X

## Candidates
### tests/unit/pricing.test.ts:17
- Mutant(s) that slipped past: 3
- Operators: CONDITIONAL_BOUNDARY, ARITHMETIC_OPERATOR, LITERAL_VALUE
- Current assertion: `expect(result).toBeTruthy()`
- Suggested replacement: `expect(result).toBe(<expected literal>)`
- Priority: P0
```

## Gate Contract
**Zero surviving mutants in P0 code AND mutation score meets the
domain threshold.** Three ways to violate and their responses:

1. Any P0 mutant survived → BLOCKED regardless of overall score.
   This is the strong rule — a P0 code path that a mutation can
   slip through is a P0 code path without a real test.
2. Overall score below threshold by less than 5% → NEEDS_REVISION
   with a "close miss — tighten the weak assertions listed in
   weak-assertions.md".
3. Overall score below threshold by more than 5% → BLOCKED.
   "Your tests cover the code but don't actually test it" is a
   merge-blocker.

No override flag. A P0 survivor that the team wants to accept
requires moving the source file out of P0 in `test-strategy.md`,
not a flag on the skill.

## Non-Goals
- Does NOT fix tests or code. It identifies weak assertions and
  points at them.
- Does NOT deduplicate equivalent mutants beyond what the catalog's
  static filter catches. Semantic equivalence in general is
  undecidable — we live with a small false-positive rate.
- Does NOT run the full test suite against every mutant if
  `test-priority-engine` has produced a priority plan for the
  affected tests; the skill reuses the plan's ordering to fail
  fast. Every mutant still gets a real run; the optimization is
  about ordering, not about skipping tests.
- Does NOT report line coverage. That's covered by
  `coverage-analyzer`.

## Downstream Dependencies
- `release-decision-engine` — reads `mutationScore` and
  `p0Survivors` as hard blocker signals; mutation score feeds
  into the weighted quality score with a domain-specific weight.
- `learning-loop-engine` — ingests `mutants.json` over time to
  spot "which operators keep surviving" as a signal that the test
  strategy has a systematic gap.
- `component-test-writer` — reads `weak-assertions.md` when
  regenerating tests, so the next iteration tightens the weak
  assertions automatically.
