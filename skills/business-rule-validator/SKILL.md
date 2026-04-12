---
name: business-rule-validator
description: Extracts business rules from the PRD as a structured catalog, generates a test case per rule, and runs semantic gap analysis against existing tests. Produces business-rules.md + br-test-suite.test.ts + semantic-gaps.md. Gate contract — zero uncovered P0 rules. PIPELINE-1 step 4.
allowed-tools: Read Grep Glob Write
context: fork
agent: Explore
---

# Business Rule Validator

An L1 Truth-Validation skill. Its job is to make the business rules
buried in the PRD **executable and auditable**: every rule becomes a
row in a catalog, a generated test case, and a line in a semantic-gap
report. The gate contract is that no P0 business rule can ship
untested.

## When You're Invoked

- During PIPELINE-1 step 4, in parallel with `component-test-writer`,
  `contract-test-writer`, and `test-data-manager`.
- On demand as `/vibeflow:business-rule-validator <prd path>`.
- Re-runs automatically when `invariant-formalizer` needs a fresh
  `business-rules.md` as input (Sprint 2 ticket S2-09).

## Input Contract

| Input | Required | Notes |
|-------|----------|-------|
| PRD | yes | `.vibeflow/artifacts/prd.md` or path arg. Must have passed `prd-quality-analyzer` with testability ≥ 60 — we do not rescue unready requirements. |
| `prd-quality-report.md` | yes | `.vibeflow/reports/prd-quality-report.md`. Its ambiguity findings become rule-extraction exclusions (ambiguous clauses cannot become rules). |
| `scenario-set.md` | optional but preferred | Output of `test-strategy-planner`; scenarios that map to an extracted rule become candidate tests for that rule. |
| Existing test files | optional | All `*.test.*` under the source directory are scanned for rule references during gap analysis. |
| Domain config | yes | `vibeflow.config.json` → `domain`. Drives priority defaults (see `references/rule-extraction.md`). |
| Priority hints | optional | `.vibeflow/artifacts/priority-hints.json` — explicit `{ ruleId: "P0"|"P1"|"P2"|"P3" }` overrides. |

**Hard preconditions** — refuse to run with a single blocks-merge finding
rather than producing a wrong catalog:

1. The PRD must parse. Malformed markdown is fixed upstream.
2. `prd-quality-report.md` testability score must be ≥ 60. If lower,
   emit a blocker pointing at the quality report — do not extract
   rules from a PRD we already know is ambiguous.
3. Every extracted rule must pass the ambiguity filter (no rule may
   quote text that the PRD quality report flagged as AMBIGUOUS).

## Algorithm

### Step 1 — Extract candidate rules
Walk the PRD section by section. For each paragraph, look for one of
the patterns defined in `references/rule-extraction.md`:

- RFC-2119 keywords (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD,
  SHOULD NOT, MAY) — the strongest signal.
- Conditional imperatives ("if X then Y") — second-strongest.
- Prohibition verbs ("cannot", "never", "not allowed") — weaker,
  needs context to disambiguate.
- Domain-specific trigger phrases (listed per domain in the reference).

Every candidate carries the exact quoted substring plus a location
anchor (`<section>#<paragraph index>`) — evidence is load-bearing.

### Step 2 — Normalize to BusinessRule records
Each candidate becomes a `BusinessRule`:

```ts
interface BusinessRule {
  id: string;            // "BR-NNNN" monotonic, per-PRD
  statement: string;     // exact quote from the PRD
  normalized: string;    // imperative "<actor> MUST <action> WHEN <condition>"
  actor: string;         // subject of the rule
  action: string;        // what the actor does
  condition: string;     // when the rule fires; "always" if unconditional
  priority: "P0" | "P1" | "P2" | "P3";
  source: { section: string; paragraphIndex: number; lineHint?: number };
  evidence: readonly string[];
  relatedScenarios: readonly string[];   // SC-xxx from scenario-set.md
}
```

Rules:
- **Normalization is lossless.** Any rewrite that loses meaning is a
  normalization bug — emit the original `statement` verbatim as a
  sanity check.
- **One rule per record.** If a paragraph bundles two rules
  (`USERS MUST X AND Y`), split into two records with correlated
  ids (`BR-0010a`, `BR-0010b`).
- **Priority defaults:** rules tagged P0 in the PRD win. Otherwise
  apply the domain default from `rule-extraction.md` (financial
  defaults tighter, general looser). Manual `priority-hints.json`
  always wins over defaults.

### Step 3 — Deduplication
Rules that say the same thing twice in different sections get merged.
Two rules are the same if their `normalized` strings compare equal
after lowercase + whitespace collapse. Merged rules carry **both**
source anchors in `source` so readers can find every place the PRD
repeats itself.

### Step 4 — Generate test cases
For each rule, emit a `describe("BR-NNNN", ...)` block containing:

1. **Happy path** — the rule's positive case (actor performs action
   under condition → expected outcome).
2. **Negative path** — the rule's rejection case (actor attempts the
   action without the required condition → rejection).
3. **Boundary** — only when the condition names a threshold (numeric
   or temporal); otherwise skipped.

Each generated test follows the Arrange-Act-Assert shape defined in
`component-test-writer/references/test-patterns.md`. Titles prefix
with the rule id and, when available, the scenario id:

    it("BR-0017 / SC-042: system rejects withdrawal when balance < amount", ...)

Every `it(...)` body ends with a `trace:` comment pointing back to
the PRD section that produced the rule — this is what
`traceability-engine` consumes for the RTM.

If the rule has no constructable inputs (e.g. references a data type
that doesn't exist yet), emit `it.skip` with `pending: "awaiting
test-data"` — never invent fixtures.

### Step 5 — Semantic gap analysis
Scan every `*.test.*` file under the source directory. For each
extracted rule, classify coverage:

- **Covered** — at least one test body contains the rule id
  (`BR-NNNN`) OR the `normalized` string substring OR the rule's
  scenario ids.
- **Weak** — covered, but the matching test has no assertion on the
  rule's action (e.g. the test only asserts the happy path while the
  rule has a prohibition). See `references/gap-taxonomy.md` for the
  full classification.
- **Contradicted** — a test explicitly asserts the opposite of the
  rule. This is always a BLOCKER regardless of priority.
- **Orphan** — a test mentions a `BR-NNNN` id that no longer exists
  in the catalog (e.g. the PRD dropped the rule but the test stuck
  around). Always surfaced as a finding.
- **Uncovered** — no matching test. Severity depends on priority
  (P0 uncovered = BLOCKER, P1 = soft warning, P2/P3 = informational).

### Step 6 — Compute the verdict
```
criticalGaps =
  uncoveredP0.length
  + contradicted.length
```

Verdict rules:

| Condition | Verdict |
|-----------|---------|
| `criticalGaps == 0` | APPROVED |
| `criticalGaps == 0` but `weakCoverage + orphans > budget(riskTolerance)` | NEEDS_REVISION |
| `criticalGaps > 0` | BLOCKED |

`budget(riskTolerance)`: low=0, medium=3, high=6 (same shape as
architecture-validator so reviewers only learn one rule).

**Gate contract: zero uncovered P0 rules and zero contradicted rules.**
No other condition can produce BLOCKED and no other condition can
suppress it.

### Step 7 — Write outputs

1. **`.vibeflow/reports/business-rules.md`** — the catalog (one
   table + one detail section per rule).
2. **`src/**/br-test-suite.test.ts`** — the generated test file(s).
   Location follows the same sibling-with-`.test.ts` convention as
   `component-test-writer`. Uses the same `@generated-by` banner and
   `@generated-start`/`@generated-end` markers so re-runs preserve
   human additions.
3. **`.vibeflow/reports/semantic-gaps.md`** — the gap analysis (see
   output contract below).

## Output Contract

### `business-rules.md`
```markdown
# Business Rules Catalog — <ISO timestamp>

## Summary
- PRD: <path>
- Rules extracted: N
- P0: a  P1: b  P2: c  P3: d
- Duplicates merged: M
- Ambiguity-filtered: K (rejected because PRD quality report flagged them)

## Rules
| id | priority | normalized | source |
|----|----------|------------|--------|
| BR-0001 | P0 | ... | §3.2 ¶2 |

## Detail
### BR-0001 — <normalized restated>
- **Statement**: "<exact quote>"
- **Actor**: <...>
- **Action**: <...>
- **Condition**: <...>
- **Evidence**: <section:¶ anchors>
- **Related scenarios**: SC-0042, SC-0043
```

### `semantic-gaps.md`
```markdown
# Semantic Gap Report — <ISO timestamp>

## Summary
- Verdict: [APPROVED|NEEDS_REVISION|BLOCKED]
- criticalGaps: N
- uncovered P0: a  |  contradicted: b
- weak: w  |  orphan: o

## Critical Gaps (gate-blocking)
For each:
- **finding**: <one-liner>
- **why**: <rule id + gap category from gap-taxonomy.md>
- **impact**: <what ships broken if ignored>
- **confidence**: <0..1>
- **evidence**: <PRD anchor + test anchor>
- **mitigation**: <concrete fix — "write a test that asserts X", never "improve coverage">

## Weak / Orphan / Uncovered (non-blocking)
<same shape, grouped by category>
```

## Explainability Contract
Every finding — in `business-rules.md` and in `semantic-gaps.md` —
MUST carry `finding / why / impact / confidence / evidence`. Gap
classifications **must** cite a category id from
`references/gap-taxonomy.md`. Undocumented classifications are
forbidden; if a diff pattern doesn't fit the taxonomy, extend the
taxonomy first.

## Non-Goals
- Does NOT generate fixtures — that's `test-data-manager`.
- Does NOT formalize rules as machine-checkable invariants — that's
  `invariant-formalizer` (S2-09), which *consumes* `business-rules.md`
  as input.
- Does NOT rewrite the PRD. Ambiguous rules get filtered out and the
  report points at them; it is the PRD author's job to fix them.

## Downstream Dependencies
- `invariant-formalizer` — consumes `business-rules.md` to generate
  machine-checkable predicates.
- `decision-recommender` — uses the rule catalog as decision context.
- `release-decision-engine` — reads `criticalGaps` as a hard blocker
  signal.
- `traceability-engine` — links `BR-NNNN` ↔ scenario ids ↔ test ids.
