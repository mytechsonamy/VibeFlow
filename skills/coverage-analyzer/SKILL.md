---
name: coverage-analyzer
description: Parses vitest/jest/istanbul coverage JSON, rolls up line/branch/function coverage to the requirement level via RTM, ranks uncovered gaps by risk, and enforces domain-specific thresholds. Gate contract — every P0 requirement has 100% coverage of its mapped lines, overall coverage meets the domain threshold, and no unjustified exclusions. PIPELINE-5 step 5 / PIPELINE-6 step 4.
allowed-tools: Read Write Grep Glob
context: fork
agent: Explore
---

# Coverage Analyzer

An L2 Truth-Execution skill. Line coverage is a lower bound on
quality — "did the tests run this line?" — but most teams stop
there. This skill adds two things that matter more:

1. **Requirement-level coverage.** It maps lines → files → tests
   → scenarios → PRD requirements via the RTM, so the report
   answers "is every P0 requirement's code actually exercised"
   instead of just "is the file average above 80%".
2. **Risk-weighted gap ranking.** The report ranks uncovered
   code by the same risk signals `test-priority-engine` uses,
   so the first thing a reader sees is "this P0 file has 40%
   churn and 0% branch coverage" not "module X is 78.3%".

Coverage is a necessary-but-not-sufficient signal; this skill
is where necessity becomes visible.

## When You're Invoked

- **PIPELINE-5 step 5** — after `regression-test-runner` +
  `mutation-test-runner` have produced their reports, before
  `release-decision-engine` computes its verdict. Coverage is
  one of the signals the decision engine weights.
- **PIPELINE-6 step 4** — same position in the release-track
  pipeline.
- **On demand** as
  `/vibeflow:coverage-analyzer [--input <path>] [--fmt istanbul|v8]`.
- **From `learning-loop-engine`** when the loop needs a fresh
  coverage snapshot to correlate with historical regression
  data.

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| Coverage summary | yes | `coverage-summary.json` (Istanbul) OR `coverage/coverage-final.json` (v8) OR a runner-specific JSON path. Auto-detect from file name + shape. |
| `rtm.md` | optional but preferred | The Requirements Traceability Matrix. When present, the skill walks `scenario → test → source file` and rolls coverage up to the PRD requirement level. |
| `scenario-set.md` | optional | Supplies scenario priorities (P0/P1/...) for the gap ranking. |
| `regression-baseline.json` | optional | Supplies test priority tags used for the P0 zero-uncovered rule. |
| `codebase-intel` MCP | optional | `ci_find_hotspots` feeds the churn component of gap prioritization. |
| Domain config | yes | `vibeflow.config.json` → `domain` drives the threshold from `references/coverage-metrics.md`. |

**Hard preconditions** — refuse rather than emit a coverage
score downstream should not trust:

1. The coverage file must parse cleanly. Malformed JSON → block
   with "coverage file is malformed; regenerate from the runner
   and try again".
2. The coverage file must cover at least one source file. An
   empty coverage run is a runner bug, not a data point.
3. The `regression-test-runner` step must have produced a PASS
   verdict on the current HEAD (or `--allow-unverified` must
   be explicit). Coverage against a broken test suite is
   meaningless — every "covered" line is covered by a failing
   test.
4. If the domain is `financial` or `healthcare` AND `rtm.md` is
   absent, the run blocks. Requirement-level coverage is the
   whole point in regulated domains, and a file-level rollup
   is not an acceptable substitute.

## Algorithm

### Step 1 — Detect + parse the coverage file
Auto-detect the format:

- **Istanbul** — top-level object keyed by file path, each value
  has `statementMap` / `fnMap` / `branchMap` / `s` / `f` / `b`
- **v8** — top-level `result` array with `url` / `functions` /
  `scriptId`
- **`coverage-summary.json`** (Istanbul summary) — simpler rollup
  format; the skill accepts it but flags "summary-only; file
  drilldown unavailable" in the report

Unknown formats block with "supported formats: istanbul,
v8, istanbul-summary — got <detected>". No silent guessing.

### Step 2 — Normalize to `CoverageRecord`
Every parsed file becomes a canonical record:

```ts
interface CoverageRecord {
  file: string;               // relative to project root
  lines: { covered: number; total: number; uncoveredLines: number[] };
  branches: { covered: number; total: number; uncoveredRanges: Array<[number, number]> };
  functions: { covered: number; total: number; uncoveredFns: string[] };
  statements: { covered: number; total: number };
}
```

The normalized shape is identical regardless of source format,
so downstream steps (rollup, ranking, gate) are source-agnostic.
If a format doesn't provide one of these (v8 has no branch data
by default), the field is set to `null` explicitly — NOT zero.
A missing signal is different from a 0% signal.

### Step 3 — Compute per-file metrics
For each `CoverageRecord`:

- `lineCoverage = lines.covered / lines.total`
- `branchCoverage = branches.covered / branches.total` (when
  available; else null)
- `functionCoverage = functions.covered / functions.total`
- `statementCoverage = statements.covered / statements.total`

Return `null` for any metric whose `total` is 0 — "a file with
no branches has 100% branch coverage" is a common footgun; the
skill surfaces it as `null` and consumers read it as "not
measurable", not "perfect".

### Step 4 — Roll up to the requirement level
When `rtm.md` is present:

1. Load the RTM's linkage matrix: `requirement → scenario → test`.
2. For every requirement, collect the set of test files that
   exercise its scenarios.
3. For every test file, collect the set of source files it
   touches (via `ci_dependency_graph` when available, else
   directory proximity fallback).
4. Compute per-requirement coverage:
   - `reqLineCoverage = Σ covered lines in mapped sources / Σ total lines in mapped sources`
   - `reqBranchCoverage = Σ covered branches / Σ total branches`
   - Per-requirement `coveredByTests: [testId, ...]` so the
     report can show which tests are pulling the weight
5. A requirement with no mapped tests has `reqLineCoverage = 0`
   AND a `mappingGap: true` flag. A requirement with a broken
   RTM linkage has `reqLineCoverage = null` AND an
   `rtmDrift: true` flag — these are different problems and
   the report distinguishes them.

### Step 5 — Rank uncovered gaps by risk
For every file with a non-empty `uncoveredLines` list, compute
a gap score using `references/gap-prioritization.md`:

```
gapScore = 0.40 * priorityComponent
         + 0.30 * criticalityComponent
         + 0.20 * churnComponent
         + 0.10 * requirementLinkComponent
```

- **priorityComponent** — max priority of tests that SHOULD have
  exercised this line (`P0 → 1.0`, `P1 → 0.7`, `P2 → 0.4`,
  `P3 → 0.15`, unknown → 0.3)
- **criticalityComponent** — 1.0 if the file is listed in
  `vibeflow.config.json.criticalPaths` (same list
  `mutation-test-runner` uses), 0.5 otherwise
- **churnComponent** — normalized commit count in the past 30
  days (from `ci_find_hotspots` when available, 0 otherwise)
- **requirementLinkComponent** — 1.0 if the file is linked to a
  P0 requirement via RTM, 0.7 for P1, 0.4 for P2, 0.15 for P3,
  0.3 for unlinked

Gap scores are in `[0, 1]`; the report sorts descending so the
highest-risk uncovered code is visible first. A tail of 0.15
P3 gaps doesn't dominate the report.

### Step 6 — Apply the gate

Two rules, both must pass:

1. **Overall threshold** — `lineCoverage >= threshold(domain)`
   using the domain thresholds from
   `references/coverage-metrics.md`.
2. **P0 zero-uncovered rule** — every file linked to a P0
   requirement (via RTM) must have `lineCoverage == 1.0` AND
   `branchCoverage == 1.0` on every branch the file's tests
   should exercise.

Verdict:

| Condition | Verdict |
|-----------|---------|
| Both rules pass | PASS |
| Rule 1 fails by less than 5% AND rule 2 passes | NEEDS_REVISION |
| Rule 1 fails by ≥ 5% AND rule 2 passes | BLOCKED |
| Rule 2 fails (any P0 gap) | BLOCKED |

**Gate contract: zero uncovered lines or branches in P0 code,
and the overall coverage meets the domain threshold.** Same
two-rule compose as `mutation-test-runner` — a score that
meets the overall bar with a P0 hole is still BLOCKED.

### Step 7 — Validate exclusions
Coverage runs typically exclude test files, generated code,
and third-party vendored files. The skill walks the coverage
file's exclusion list and applies this rule:

- Exclusions declared in `test-strategy.md →
  coverageExcludeReasons` with a text rationale are ALLOWED
- Exclusions applied by the runner itself (via
  `/* istanbul ignore next */` inline comments or pattern
  exclusions in the config) are recorded with their source
  line. The report lists them and flags if more than 5% of
  the codebase is excluded (at that point, exclusions are
  shaping the score more than the tests are)
- Exclusions that apply to a file listed in `criticalPaths`
  BLOCK the run unconditionally. No matter how good the
  rationale is, excluding a critical path from coverage is
  how real gaps ship. The run tells the operator "remove
  this exclusion, tighten the critical-path list, or open a
  governance discussion"

### Step 8 — Write outputs

1. **`.vibeflow/reports/coverage-report.md`** — human-readable
   report (see contract below)
2. **`.vibeflow/artifacts/coverage/<runId>/per-file.json`** —
   every `CoverageRecord` with computed metrics + gap score
3. **`.vibeflow/artifacts/coverage/<runId>/requirements.json`**
   — per-requirement rollup (only when `rtm.md` was present)
4. **`.vibeflow/artifacts/coverage/<runId>/excluded.json`** —
   exclusion audit trail with source lines

## Output Contract

### `coverage-report.md`
```markdown
# Coverage Report — <runId>

## Header
- Run id: <runId>
- Domain: financial
- Threshold: 0.90 (financial)
- Source format: istanbul | v8 | istanbul-summary
- Files scanned: N
- Requirements rolled up: R  (mapping gaps: G, RTM drift: D)
- Verdict: PASS | NEEDS_REVISION | BLOCKED

## Summary
- Line coverage: XX.X% (vs 90.0% threshold)
- Branch coverage: YY.Y%
- Function coverage: ZZ.Z%
- Statement coverage: WW.W%
- **P0 zero-uncovered rule: 0 gaps** (gate-blocking if > 0)
- Excluded lines: E (X% of total)

## Requirement coverage
| PRD | Scenarios | Tests | Line | Branch | Gap? |
|-----|-----------|-------|------|--------|------|
| PRD-§3.2 | SC-112, SC-113 | 4 | 100% | 100% | — |
| PRD-§4.1 | SC-114 | 2 | 73% | 62% | mappingGap |

## Top risk gaps
### src/pricing/promo.ts
- Gap score: 0.92
- Priority: P0 (via SC-112)
- Line coverage: 40% (uncovered: 42-58, 67, 71-80)
- Branch coverage: 25% (uncovered branches: discount expired, stacked promos)
- Churn: 12 commits / 30 days
- Requirement link: PRD-§3.2
- Tests that should exercise this: tests/unit/promo.test.ts (exists but doesn't hit the uncovered branches)

## Excluded lines
### src/legacy/adapter.ts
- Reason: vendored third-party adapter
- Source: test-strategy.md → coverageExcludeReasons[adapter]
- Critical path? No

## RTM gaps + drift
- Mapping gaps (requirement with no test): N → <list>
- RTM drift (broken linkage): D → <list>
```

## Gate Contract
**Zero uncovered lines or branches in P0 code, overall coverage
meets the domain threshold, no exclusions on critical paths.**
Three ways to violate:

1. Any P0-linked file has `lineCoverage < 1.0` OR
   `branchCoverage < 1.0` → BLOCKED regardless of overall
2. Overall `lineCoverage` is below threshold by less than 5% →
   NEEDS_REVISION (close miss — tighten specific files)
3. Overall `lineCoverage` is below threshold by ≥ 5% OR any
   exclusion applies to a `criticalPaths` file → BLOCKED

No override flag. A project that genuinely wants to ship with
P0 coverage gaps has to either move the file out of a P0
requirement's mapping OR open a governance discussion; there's
no config knob that opens the gate.

## Non-Goals
- Does NOT write tests. It ranks gaps; the fix is
  `component-test-writer` / human.
- Does NOT track coverage over time. That's
  `learning-loop-engine`'s job; this skill emits the current
  snapshot.
- Does NOT compute mutation score. Mutation is a separate
  signal — line coverage without mutation is a lie, and the
  two are correlated but distinct (see
  `mutation-test-runner/references/score-thresholds.md` §3).
- Does NOT re-run tests to get coverage. It reads what the
  last runner produced and fails loudly if that file is
  stale / missing / malformed.
- Does NOT silently ignore branch coverage when v8 is the
  source. A v8 run that lacks branch data reports
  `branchCoverage: null` and the verdict treats "null" as
  "not measurable" — it neither passes nor fails the branch
  component of the gate.

## Downstream Dependencies
- `release-decision-engine` — reads `per-file.json` and
  `requirements.json` as weighted quality score inputs.
  `p0Uncovered` feeds the hard-blocker list alongside
  `mutation.p0Survivors` and `business-rule.criticalGaps`.
- `learning-loop-engine` — ingests coverage snapshots over
  time to correlate coverage movement with regression
  history.
- `test-priority-engine` — uses `per-file.json` to bias
  risk scores toward under-covered files in future runs.
- `traceability-engine` — reads `requirements.json` to keep
  the RTM current with real coverage data.
