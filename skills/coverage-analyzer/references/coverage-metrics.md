# Coverage Metrics

Every formula, domain threshold, and rollup rule the
`coverage-analyzer` skill uses at Steps 3, 4, and 6 of its
algorithm. This file is the single source of truth — changing
any value here is a governance move, not a config tweak.

**Current metrics config version: 1**

---

## 1. Per-file metrics

For every `CoverageRecord`, the skill computes four metrics
independently. Each metric is a ratio in `[0, 1]` or `null`
(when the denominator is 0).

### 1.1 Line coverage

```
lineCoverage(file) = lines.covered / lines.total
```

- Denominator is zero → return `null`, NOT zero. A file with
  no executable lines is "not measurable", not "perfectly
  uncovered".
- The skill reports `uncoveredLines` as an explicit array of
  line numbers so downstream tools (the report, the gap
  ranker) can point at specific places instead of a count.

### 1.2 Branch coverage

```
branchCoverage(file) = branches.covered / branches.total
```

- Istanbul provides branch data by default; v8 does NOT. A v8
  run sets `branchCoverage: null` for every file — the
  downstream gate treats `null` as "not measurable", not as
  a failure.
- **A v8-source report in a `financial` / `healthcare`
  domain blocks** with remediation "use istanbul coverage for
  regulated domains; v8 lacks branch data". Those domains
  require branch coverage by policy, and we'd rather refuse
  to emit a report than silently report 100% branch (because
  the metric is null, not because it's perfect).

### 1.3 Function coverage

```
functionCoverage(file) = functions.covered / functions.total
```

- `uncoveredFns` is an array of function names so the report
  can name specific dead code.

### 1.4 Statement coverage

```
statementCoverage(file) = statements.covered / statements.total
```

- Statement coverage is usually within a few percent of line
  coverage in real code. It's reported as a separate metric
  for visibility but the gate doesn't use it — line coverage
  subsumes it for practical purposes.

---

## 2. Rollup rules

### 2.1 File → project

```
projectLineCoverage = Σ covered lines / Σ total lines       // NOT average of per-file %
```

**We sum numerators and denominators, never average
percentages.** "Average of per-file percentages" gives a 1000-
line file and a 10-line file equal weight; "sum of
numerators" gives them proportional weight. The denominator-
weighted aggregate is the honest one for a gate.

### 2.2 File → requirement (via RTM)

When `rtm.md` is present:

1. For each requirement, collect its mapped test files from
   `rtm.md`.
2. For each test file, walk `ci_dependency_graph` to find
   source files it touches (transitively).
3. Collect the UNION of those source files per requirement.
4. Compute coverage on the union:

```
reqLineCoverage = Σ covered lines in union / Σ total lines in union
reqBranchCoverage = Σ covered branches in union / Σ total branches in union
```

Edge cases:

- **Requirement with zero mapped tests** → `reqLineCoverage = 0`
  AND `mappingGap: true`. A requirement that isn't mapped is
  a bigger problem than one with low coverage, and the report
  surfaces it as such.
- **Requirement with broken RTM linkage** (e.g. links to a
  scenario that doesn't exist) → `reqLineCoverage = null` AND
  `rtmDrift: true`. Distinct from `mappingGap` because the
  remediation is different: fix the RTM, not add tests.
- **Source file touched by tests from TWO requirements** →
  counted once per requirement's union. A line that serves
  two features is covered when either feature's tests run it.

### 2.3 Project-level rollup across metrics

The project-level dashboard shows four independent rollups
(line / branch / function / statement). We do NOT compute a
single "weighted overall" number — each metric is its own
signal, and averaging them would hide specific weaknesses.

---

## 3. Domain thresholds

Project-wide line-coverage thresholds by domain. Branch and
function thresholds track line minus 5% (the branch target is
slightly lower in practice because real code has branches
that are hard to reach without contrived tests).

| Domain | Line target | Branch target | Function target |
|--------|-------------|---------------|-----------------|
| `financial` | **0.90** | 0.85 | 0.95 |
| `healthcare` | **0.90** | 0.85 | 0.95 |
| `e-commerce` | **0.80** | 0.75 | 0.85 |
| `general` | **0.75** | 0.70 | 0.80 |

### Threshold bands

The skill uses a ±5% close-miss band around the line target:

- `lineCoverage >= target` → PASS (rule 1)
- `target - 5% <= lineCoverage < target` → NEEDS_REVISION
- `lineCoverage < target - 5%` → BLOCKED

The `P0 zero-uncovered` rule is independent — it can BLOCK a
run whose overall is comfortably above the threshold. See
SKILL.md §Step 6 for the two-rule compose.

### Why the financial / healthcare gap over e-commerce / general

The same rationale as `mutation-test-runner`'s domain
thresholds: failure cost is non-reversible in regulated
domains (money gone, audits, regulatory exposure), so the
coverage bar has to be higher. The 10-point gap between
financial and e-commerce is deliberate — it reflects the
real cost difference of a bug slipping through in each
context.

---

## 4. P0 zero-uncovered rule

**Every file linked to a P0 requirement must have line and
branch coverage of 1.0, on every covered path the test set
should exercise.**

- "Linked to a P0 requirement" means there's an RTM path from
  the file to a scenario with `priority: P0`. The skill walks
  this via `requirements.json`.
- "Line and branch coverage of 1.0" is exact. Not 0.99,
  not "within rounding". The P0 rule is the gate's hardest
  edge, intentionally.
- A P0 file with an exclusion applied to it BLOCKS the run
  regardless of the exclusion's rationale. Critical-path
  exclusion is how real gaps ship.
- `null` branch coverage (from v8 source) on a P0 file blocks
  with remediation "switch to istanbul for P0 files; branch
  coverage must be measurable".

### What counts as "the test set should exercise"

The skill computes this set conservatively:

1. Start with the file's set of executable lines + branches.
2. Subtract lines declared `// @coverage-exempt: <reason>`
   inline (reviewer-audited exemptions; mandatory reason; see
   §5 for rules).
3. The remainder is the "should exercise" set. Coverage is
   `(covered ∩ should) / should`.

Inline exemption is NOT the same as a runner ignore. Runner
ignores disappear from the file's total lines; inline
exemptions stay in the total and just don't contribute to
the "should" set. The distinction matters because it keeps
the exemption auditable — a big exemption count tells you
the file is effectively untested at the edges.

---

## 5. Exclusion rules

Coverage files come with exclusions. The skill walks them:

### 5.1 Allowed exclusions

- **`test-strategy.md → coverageExcludeReasons`** — explicit
  file + glob list with a text `reason` per entry. Fully
  auditable.
- **`// istanbul ignore next`** and variants inline — allowed
  only when the line also has a `// @reason: <text>` comment
  on the same or previous line. Reasonless ignores are
  rejected.
- **Runner config patterns** — honored for globally-excluded
  directories (`node_modules`, `dist`, `build`), listed in
  the report so the auditor can see them.

### 5.2 Forbidden exclusions

- **A `criticalPaths` file excluded ANYWHERE**. The file can
  be in `criticalPaths` and still have a per-line
  `@coverage-exempt` annotation (that's how you carve out a
  specific not-testable block), but the WHOLE FILE cannot be
  excluded via test-strategy or runner config. This is the
  non-negotiable rule — critical-path exclusions block the
  run with remediation "remove the exclusion, shrink the
  critical-path list, or open a governance discussion".
- **Exclusions with no reason**. Reasonless exclusions are
  rejected at load. "I'll add a reason later" is not a reason.
- **Exclusions that hide more than 5% of the codebase in
  total**. Exclusions at that volume are shaping the score
  more than the tests are; the report flags it and the gate
  reviews it.

### 5.3 What the report shows

- Every exclusion with its source (test-strategy / inline /
  runner config), the reason, and whether it applies to a
  critical-path file
- The total percentage of lines excluded AND an `exclusionImpact`
  score showing how much the overall coverage would differ if
  all exclusions were removed

---

## 6. Version bump discipline

Same as `mutation-test-runner`'s score thresholds:

1. Retrospective on ≥10 historical runs showing the new
   thresholds capture a real weakness the old ones missed
2. `metricsConfigVersion` bump (recorded in every report
   header)
3. Migration note in the PR
4. Integration harness sentinel update

Silent edits to this file fail CI. The current values are
load-bearing for every downstream consumer, and changing them
is a real change.

---

## 7. What these metrics do NOT do

- **Don't measure meaningful coverage.** Line coverage says
  "this line ran"; mutation coverage says "a test would fail
  if this line were wrong". The two are correlated but
  independent, and this skill does not pretend one replaces
  the other. See `mutation-test-runner/references/score-thresholds.md`
  §3 on the "no-coverage counts as survived" rule.
- **Don't measure requirement fulfillment.** High coverage on
  requirement X's files doesn't mean the requirement is met
  — it means the code is exercised. Requirement fulfillment
  is `business-rule-validator`'s job.
- **Don't measure test quality.** A test that runs a line
  but never asserts on its effect still counts for coverage
  but not mutation. Both signals are needed.
- **Don't average branch into line.** Each metric is its own
  signal. A combined "overall coverage" number would hide the
  specific gap (tests exist but don't check branches) that
  mutation testing catches.
